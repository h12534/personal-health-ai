import json
import time
from datetime import UTC, datetime, timedelta
from decimal import Decimal
from hashlib import sha256
from uuid import UUID

import structlog
from pydantic import ValidationError
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings
from app.core.errors import AppError
from app.models.food import FoodItem
from app.models.meal import MealLog
from app.models.meal_analysis import (
    AIUsageLog,
    MealAnalysisItem,
    MealAnalysisSession,
    MealImage,
    PersonalFoodMemory,
)
from app.providers.ai.base import VisionProvider, VisionProviderResponse
from app.providers.storage.base import StorageProvider
from app.repositories.food_repository import FoodRepository
from app.repositories.meal_analysis_repository import MealAnalysisRepository
from app.repositories.meal_repository import MealRepository
from app.repositories.profile_repository import ProfileRepository
from app.schemas.meal import MealRead, MealType
from app.schemas.meal_analysis import (
    MealAnalysisConfirm,
    MealAnalysisItemCreate,
    MealAnalysisItemPatch,
    MealAnalysisItemRead,
    MealAnalysisRead,
    MealAnalysisTotals,
    VisionFoodDetection,
    VisionMealResult,
)
from app.services.food_matching_service import FoodMatchingService
from app.services.image_validation_service import ImageValidationService
from app.services.meal_service import MealService
from app.services.nutrition_range_service import NutritionRangeService
from app.utils.text import normalize_food_name

logger = structlog.get_logger()
ZERO = Decimal("0")


class MealAnalysisService:
    def __init__(
        self,
        session: AsyncSession,
        settings: Settings,
        provider: VisionProvider,
        storage: StorageProvider,
    ) -> None:
        self.session = session
        self.settings = settings
        self.provider = provider
        self.storage = storage
        self.analyses = MealAnalysisRepository(session)
        self.foods = FoodRepository(session)
        self.profiles = ProfileRepository(session)

    async def create(
        self,
        user_id: UUID,
        image_bytes: bytes,
        content_type: str | None,
        idempotency_key: str | None,
        location_context: str | None = None,
        meal_type: MealType | None = None,
        eaten_at: datetime | None = None,
        note: str | None = None,
    ) -> MealAnalysisRead:
        key = (idempotency_key or sha256(image_bytes).hexdigest()).strip()[:128]
        existing = await self.analyses.by_idempotency(user_id, key)
        if existing is not None:
            return self._read(existing)
        today = datetime.now(UTC).replace(hour=0, minute=0, second=0, microsecond=0)
        count = await self.analyses.count_created_since(user_id, today)
        if count >= self.settings.vision_daily_limit:
            raise AppError(
                "vision_daily_limit_reached",
                "Today's meal photo analysis limit has been reached.",
                429,
            )
        profile = await self.profiles.by_user(user_id)
        if self.provider.is_remote and not (
            profile is not None and profile.allow_third_party_vision
        ):
            raise AppError(
                "third_party_vision_consent_required",
                "Enable third-party meal image analysis in privacy settings first.",
                403,
            )
        validator = ImageValidationService(
            self.settings.max_upload_bytes,
            self.settings.vision_max_pixels,
            self.settings.vision_max_dimension,
        )
        image = validator.validate_and_sanitize(image_bytes, content_type)
        now = datetime.now(UTC)
        draft_expires_at = now + timedelta(hours=self.settings.meal_analysis_draft_ttl_hours)
        object_key = await self.storage.put_private(
            image.data,
            image.content_type,
            image.suffix,
            now.strftime("meal-analysis/%Y/%m"),
        )
        retain_forever = bool(profile and profile.retain_meal_images)
        retention_expires = None
        if not retain_forever:
            if self.settings.meal_image_retention_days == 0:
                retention_expires = draft_expires_at
            else:
                retention_expires = now + timedelta(days=self.settings.meal_image_retention_days)
        stored = MealImage(
            user_id=user_id,
            object_key=object_key,
            content_type=image.content_type,
            size_bytes=len(image.data),
            width=image.width,
            height=image.height,
            sha256=image.sha256,
            retention_expires_at=retention_expires,
        )
        analysis = MealAnalysisSession(
            user_id=user_id,
            image=stored,
            status="pending",
            provider=self.provider.name,
            model=self.provider.model,
            prompt_version=self.settings.vision_prompt_version,
            idempotency_key=key,
            location_context=location_context,
            meal_type=meal_type,
            eaten_at=eaten_at.astimezone(UTC) if eaten_at else None,
            note=note,
            warnings=[],
            expires_at=draft_expires_at,
        )
        self.session.add(analysis)
        try:
            await self.session.commit()
            await self.session.refresh(analysis)
        except Exception:
            await self.session.rollback()
            await self.storage.delete(object_key)
            duplicate = await self.analyses.by_idempotency(user_id, key)
            if duplicate is not None:
                return self._read(duplicate)
            raise
        logger.info("meal_analysis_created", analysis_id=str(analysis.id), user_id=str(user_id))
        loaded = await self.analyses.by_id(user_id, analysis.id)
        assert loaded is not None
        return self._read(loaded)

    async def process(self, analysis_id: UUID) -> MealAnalysisRead | None:
        analysis = await self.analyses.for_worker(analysis_id, lock=True)
        if analysis is None or analysis.status != "pending":
            return None
        analysis.status = "processing"
        analysis.attempt_count += 1
        analysis.error_code = None
        analysis.error_message = None
        await self.session.commit()
        started = time.perf_counter()
        response: VisionProviderResponse | None = None
        try:
            image_bytes = await self.storage.read_bytes(analysis.image.object_key)
            response = await self.provider.analyze_meal(
                image_bytes,
                analysis.image.content_type,
                {
                    "location_context": analysis.location_context,
                    "meal_type": analysis.meal_type,
                    "prompt_version": analysis.prompt_version,
                },
            )
            result = VisionMealResult.model_validate(response.payload)
            if result.no_food_detected:
                await self._mark_failed(
                    analysis,
                    "no_food_detected",
                    "No recognizable food was found. Try a clearer, well-lit meal photo.",
                    started,
                    response,
                )
                return self._read(analysis)
            for previous in list(analysis.items):
                await self.session.delete(previous)
            await self.session.flush()
            warnings = list(result.warnings)
            position = 0
            for detection in result.foods:
                item = await self._detection_item(analysis, detection, position)
                analysis.items.append(item)
                if item.matched_food_id is None:
                    warnings.append(f"“{item.detected_name}”未匹配食物库，请手动选择。")
                position += 1
                if detection.possible_oil_weight is not None:
                    oil = await self._oil_item(analysis, detection, position)
                    analysis.items.append(oil)
                    if oil.matched_food_id is None:
                        warnings.append("估算了烹饪油，但食物库中未找到食用油条目。")
                    position += 1
            analysis.status = "completed"
            analysis.provider = response.provider
            analysis.model = response.model
            analysis.overall_confidence = result.overall_confidence
            analysis.warnings = list(dict.fromkeys(warnings))[:20]
            analysis.raw_provider_response = self._bounded_raw(response)
            self._add_usage(analysis, started, response, "completed", None)
            await self.session.commit()
            loaded = await self.analyses.for_worker(analysis.id)
            assert loaded is not None
            logger.info("meal_analysis_completed", analysis_id=str(analysis.id))
            return self._read(loaded)
        except (ValidationError, ValueError, TypeError, KeyError):
            await self._mark_failed(
                analysis,
                "invalid_vision_response",
                "The vision provider returned an invalid meal result. Please retry.",
                started,
                response,
            )
            logger.warning("meal_analysis_invalid_response", analysis_id=str(analysis.id))
            return self._read(analysis)
        except AppError as exc:
            await self._mark_failed(analysis, exc.code, exc.message, started, response)
            return self._read(analysis)
        except Exception:
            await self._mark_failed(
                analysis,
                "vision_processing_failed",
                "Meal analysis failed. Please retry.",
                started,
                response,
            )
            logger.exception("meal_analysis_failed", analysis_id=str(analysis.id))
            return self._read(analysis)

    async def get(self, user_id: UUID, analysis_id: UUID) -> MealAnalysisRead:
        return self._read(await self._owned(user_id, analysis_id))

    async def patch_item(
        self,
        user_id: UUID,
        analysis_id: UUID,
        item_id: UUID,
        payload: MealAnalysisItemPatch,
    ) -> MealAnalysisRead:
        analysis = await self._editable(user_id, analysis_id)
        item = await self.analyses.item(analysis.id, item_id)
        if item is None:
            raise AppError("analysis_item_not_found", "Analysis item was not found.", 404)
        values = payload.model_dump(exclude_unset=True)
        if "matched_food_id" in values:
            food_id = values.pop("matched_food_id")
            item.matched_food = await self._visible_food(user_id, food_id) if food_id else None
            item.matched_food_id = food_id
            item.match_type = "manual" if food_id else "unmatched"
            item.match_confidence = Decimal("1") if food_id else ZERO
        for field, value in values.items():
            setattr(item, field, value)
        if (
            item.min_weight_g > item.estimated_weight_g
            or item.max_weight_g < item.estimated_weight_g
        ):
            raise AppError(
                "invalid_weight_range",
                "Estimated weight must remain inside the minimum and maximum range.",
                422,
            )
        item.user_modified = True
        self._apply_nutrition(item)
        await self.session.commit()
        return self._read(await self._owned(user_id, analysis_id))

    async def add_item(
        self, user_id: UUID, analysis_id: UUID, payload: MealAnalysisItemCreate
    ) -> MealAnalysisRead:
        analysis = await self._editable(user_id, analysis_id)
        food = await self._visible_food(user_id, payload.food_id)
        minimum = payload.min_weight_g or payload.estimated_weight_g
        maximum = payload.max_weight_g or payload.estimated_weight_g
        if not minimum <= payload.estimated_weight_g <= maximum:
            raise AppError("invalid_weight_range", "The supplied weight range is invalid.", 422)
        item = MealAnalysisItem(
            session=analysis,
            matched_food=food,
            position=max((value.position for value in analysis.items), default=-1) + 1,
            detected_name=payload.detected_name or food.name,
            match_type="manual",
            match_confidence=Decimal("1"),
            recognition_confidence=Decimal("1"),
            portion_confidence=Decimal("1"),
            estimated_weight_g=payload.estimated_weight_g,
            min_weight_g=minimum,
            max_weight_g=maximum,
            original_ai_weight_g=None,
            portion_description=payload.portion_description,
            cooking_method=None,
            visible_components=[],
            possible_hidden_ingredients=[],
            is_hidden_ingredient=False,
            user_modified=True,
        )
        self._apply_nutrition(item)
        self.session.add(item)
        await self.session.commit()
        return self._read(await self._owned(user_id, analysis_id))

    async def delete_item(
        self, user_id: UUID, analysis_id: UUID, item_id: UUID
    ) -> MealAnalysisRead:
        await self._editable(user_id, analysis_id)
        item = await self.analyses.item(analysis_id, item_id)
        if item is None:
            raise AppError("analysis_item_not_found", "Analysis item was not found.", 404)
        item.deleted_at = datetime.now(UTC)
        await self.session.commit()
        return self._read(await self._owned(user_id, analysis_id))

    async def prepare_reanalysis(self, user_id: UUID, analysis_id: UUID) -> MealAnalysisRead:
        analysis = await self._editable(user_id, analysis_id, allow_failed=True)
        if analysis.reanalysis_count >= self.settings.vision_reanalysis_limit:
            raise AppError(
                "reanalysis_limit_reached",
                "This photo has reached the reanalysis limit.",
                429,
            )
        analysis.reanalysis_count += 1
        analysis.status = "pending"
        analysis.error_code = None
        analysis.error_message = None
        await self.session.commit()
        return self._read(await self._owned(user_id, analysis_id))

    async def delete(self, user_id: UUID, analysis_id: UUID) -> None:
        analysis = await self._owned(user_id, analysis_id)
        if analysis.status == "confirmed":
            raise AppError(
                "confirmed_analysis_locked",
                "A confirmed analysis cannot be deleted from meal history here.",
                409,
            )
        now = datetime.now(UTC)
        analysis.deleted_at = now
        analysis.status = "expired"
        analysis.raw_provider_response = None
        analysis.image.deleted_at = now
        await self.session.commit()
        await self.storage.delete(analysis.image.object_key)

    async def confirm(
        self,
        user_id: UUID,
        analysis_id: UUID,
        payload: MealAnalysisConfirm,
        idempotency_key: str | None,
    ) -> MealRead:
        analysis = await self.analyses.by_id_for_update(user_id, analysis_id)
        if analysis is None:
            raise AppError("analysis_not_found", "Meal analysis was not found.", 404)
        if analysis.status == "confirmed" and analysis.confirmed_meal_id is not None:
            meal = await MealRepository(self.session).by_id(user_id, analysis.confirmed_meal_id)
            if meal is None:
                raise AppError("meal_not_found", "Confirmed meal was not found.", 404)
            return MealService._read(meal)
        if analysis.status != "completed":
            raise AppError(
                "analysis_not_ready",
                "Only a completed analysis draft can be confirmed.",
                409,
            )
        active = [item for item in analysis.items if item.deleted_at is None]
        if not active:
            raise AppError("empty_analysis", "Add at least one food before confirming.", 422)
        overrides = {item.analysis_item_id: item for item in payload.items or []}
        if payload.items is not None and set(overrides) != {item.id for item in active}:
            raise AppError(
                "incomplete_confirmation",
                "Confirmation items must include every active analysis item exactly once.",
                422,
            )
        meal = MealLog(
            user_id=user_id,
            meal_type=payload.meal_type,
            eaten_at=payload.eaten_at.astimezone(UTC),
            note=payload.note,
            source="vision_confirmed",
            idempotency_key=f"vision:{analysis.id}",
            items=[],
        )
        for draft_item in active:
            override = overrides.get(draft_item.id)
            food_id = override.food_id if override else draft_item.matched_food_id
            weight = override.weight_g if override else draft_item.estimated_weight_g
            if food_id is None:
                raise AppError(
                    "unmatched_analysis_item",
                    f"Choose a food match for {draft_item.detected_name} before saving.",
                    422,
                )
            food = await self._visible_food(user_id, food_id)
            meal_item = MealService._make_item(food, weight, "g", str(draft_item.id))
            meal_item.nutrition_source = f"vision_confirmed:{food.source}"[:64]
            meal.items.append(meal_item)
            if draft_item.original_ai_weight_g is not None:
                await self._remember_correction(user_id, analysis, draft_item, food_id, weight)
        MealService._recalculate(meal)
        self.session.add(meal)
        await self.session.flush()
        analysis.status = "confirmed"
        analysis.confirmed_meal_id = meal.id
        analysis.confirmed_at = datetime.now(UTC)
        analysis.confirm_idempotency_key = (idempotency_key or "")[:128] or None
        analysis.meal_type = payload.meal_type
        analysis.eaten_at = payload.eaten_at.astimezone(UTC)
        analysis.note = payload.note
        profile = await self.profiles.by_user(user_id)
        delete_image_after_confirm = self.settings.meal_image_retention_days == 0 and not (
            profile is not None and profile.retain_meal_images
        )
        if delete_image_after_confirm:
            analysis.image.retention_expires_at = datetime.now(UTC)
        await self.session.commit()
        if delete_image_after_confirm:
            try:
                await self.storage.delete(analysis.image.object_key)
                analysis.image.deleted_at = datetime.now(UTC)
                await self.session.commit()
            except Exception:
                logger.exception(
                    "meal_analysis_image_delete_failed",
                    analysis_id=str(analysis.id),
                    image_id=str(analysis.image.id),
                )
        logger.info(
            "meal_analysis_confirmed",
            analysis_id=str(analysis.id),
            meal_id=str(meal.id),
            user_id=str(user_id),
        )
        return MealService._read(meal)

    async def cleanup_expired(self) -> tuple[int, int]:
        now = datetime.now(UTC)
        sessions = list(
            (
                await self.session.scalars(
                    select(MealAnalysisSession).where(
                        MealAnalysisSession.status.not_in(["confirmed", "expired"]),
                        MealAnalysisSession.expires_at <= now,
                    )
                )
            ).all()
        )
        for analysis in sessions:
            analysis.status = "expired"
            analysis.raw_provider_response = None
        raw_cutoff = now - timedelta(days=self.settings.vision_raw_response_retention_days)
        raw_sessions = list(
            (
                await self.session.scalars(
                    select(MealAnalysisSession).where(
                        MealAnalysisSession.raw_provider_response.is_not(None),
                        MealAnalysisSession.updated_at <= raw_cutoff,
                    )
                )
            ).all()
        )
        for analysis in raw_sessions:
            analysis.raw_provider_response = None
        images = list(
            (
                await self.session.scalars(
                    select(MealImage).where(
                        MealImage.deleted_at.is_(None),
                        MealImage.retention_expires_at.is_not(None),
                        MealImage.retention_expires_at <= now,
                    )
                )
            ).all()
        )
        for image in images:
            await self.storage.delete(image.object_key)
            image.deleted_at = now
        usage_cutoff = now - timedelta(days=self.settings.ai_usage_retention_days)
        usage_result = await self.session.execute(
            delete(AIUsageLog).where(AIUsageLog.created_at < usage_cutoff)
        )
        await self.session.commit()
        rowcount = getattr(usage_result, "rowcount", 0) or 0
        return len(images), int(rowcount)

    async def _detection_item(
        self,
        analysis: MealAnalysisSession,
        detection: VisionFoodDetection,
        position: int,
    ) -> MealAnalysisItem:
        match = await FoodMatchingService(self.session).match(
            analysis.user_id,
            detection.detected_name,
            detection.aliases,
            analysis.location_context,
        )
        item = MealAnalysisItem(
            session_id=analysis.id,
            matched_food_id=match.food.id if match.food else None,
            matched_food=match.food,
            position=position,
            detected_name=detection.detected_name,
            match_type=match.match_type,
            match_confidence=Decimal(str(match.confidence)),
            recognition_confidence=detection.recognition_confidence,
            portion_confidence=detection.portion_confidence,
            estimated_weight_g=detection.estimated_weight_g,
            min_weight_g=detection.weight_range.min_g,
            max_weight_g=detection.weight_range.max_g,
            original_ai_weight_g=detection.estimated_weight_g,
            portion_description=detection.portion_description,
            cooking_method=detection.cooking_method,
            visible_components=detection.visible_components,
            possible_hidden_ingredients=detection.possible_hidden_ingredients,
            is_hidden_ingredient=False,
            user_modified=False,
        )
        self._apply_nutrition(item)
        return item

    async def _oil_item(
        self,
        analysis: MealAnalysisSession,
        detection: VisionFoodDetection,
        position: int,
    ) -> MealAnalysisItem:
        assert detection.possible_oil_weight is not None
        minimum = detection.possible_oil_weight.min_g
        maximum = detection.possible_oil_weight.max_g
        center = (minimum + maximum) / Decimal("2")
        match = await FoodMatchingService(self.session).match(
            analysis.user_id, "食用油", ["烹调油"], analysis.location_context
        )
        item = MealAnalysisItem(
            session_id=analysis.id,
            matched_food_id=match.food.id if match.food else None,
            matched_food=match.food,
            position=position,
            detected_name=f"{detection.detected_name}的估算烹饪油",
            match_type=match.match_type,
            match_confidence=Decimal(str(match.confidence)),
            recognition_confidence=detection.recognition_confidence,
            portion_confidence=min(detection.portion_confidence, Decimal("0.6")),
            estimated_weight_g=center,
            min_weight_g=minimum,
            max_weight_g=maximum,
            original_ai_weight_g=center,
            portion_description="可能使用的烹饪油",
            cooking_method=detection.cooking_method,
            visible_components=[],
            possible_hidden_ingredients=["食用油"],
            is_hidden_ingredient=True,
            user_modified=False,
        )
        self._apply_nutrition(item)
        return item

    @staticmethod
    def _apply_nutrition(item: MealAnalysisItem) -> None:
        food = item.matched_food
        if food is None:
            for field in (
                "calories",
                "protein",
                "carbs",
                "fat",
                "fiber",
                "min_calories",
                "max_calories",
                "min_protein",
                "max_protein",
                "min_carbs",
                "max_carbs",
                "min_fat",
                "max_fat",
                "min_fiber",
                "max_fiber",
            ):
                setattr(item, field, ZERO)
            return
        values = NutritionRangeService.calculate(
            food, item.estimated_weight_g, item.min_weight_g, item.max_weight_g
        )
        item.calories = values.center.calories
        item.protein = values.center.protein
        item.carbs = values.center.carbs
        item.fat = values.center.fat
        item.fiber = values.center.fiber
        item.min_calories = values.minimum.calories
        item.max_calories = values.maximum.calories
        item.min_protein = values.minimum.protein
        item.max_protein = values.maximum.protein
        item.min_carbs = values.minimum.carbs
        item.max_carbs = values.maximum.carbs
        item.min_fat = values.minimum.fat
        item.max_fat = values.maximum.fat
        item.min_fiber = values.minimum.fiber
        item.max_fiber = values.maximum.fiber

    async def _mark_failed(
        self,
        analysis: MealAnalysisSession,
        code: str,
        message: str,
        started: float,
        response: VisionProviderResponse | None,
    ) -> None:
        analysis.status = "failed"
        analysis.error_code = code
        analysis.error_message = message
        if response is not None:
            analysis.raw_provider_response = self._bounded_raw(response)
        self._add_usage(analysis, started, response, "failed", code)
        await self.session.commit()

    def _add_usage(
        self,
        analysis: MealAnalysisSession,
        started: float,
        response: VisionProviderResponse | None,
        status: str,
        error_code: str | None,
    ) -> None:
        self.session.add(
            AIUsageLog(
                user_id=analysis.user_id,
                analysis_session_id=analysis.id,
                provider=response.provider if response else analysis.provider,
                model=response.model if response else analysis.model,
                input_tokens=response.input_tokens if response else None,
                output_tokens=response.output_tokens if response else None,
                image_count=1,
                latency_ms=max(0, round((time.perf_counter() - started) * 1000)),
                estimated_cost=(
                    Decimal(str(response.estimated_cost))
                    if response and response.estimated_cost is not None
                    else None
                ),
                status=status,
                error_code=error_code,
            )
        )

    def _bounded_raw(self, response: VisionProviderResponse) -> dict[str, object]:
        raw = response.raw_response or {"payload": response.payload}
        encoded = json.dumps(raw, ensure_ascii=False, default=str)
        if len(encoded) <= self.settings.vision_raw_response_max_chars:
            parsed: dict[str, object] = json.loads(encoded)
            return parsed
        return {
            "truncated": True,
            "provider": response.provider,
            "model": response.model,
            "characters": len(encoded),
        }

    async def _remember_correction(
        self,
        user_id: UUID,
        analysis: MealAnalysisSession,
        item: MealAnalysisItem,
        food_id: UUID,
        confirmed_weight: Decimal,
    ) -> None:
        label = normalize_food_name(item.detected_name)
        location = analysis.location_context or "unspecified"
        memory = await self.session.scalar(
            select(PersonalFoodMemory).where(
                PersonalFoodMemory.user_id == user_id,
                PersonalFoodMemory.normalized_detected_label == label,
                PersonalFoodMemory.confirmed_food_id == food_id,
                PersonalFoodMemory.location_context == location,
            )
        )
        ai_weight = item.original_ai_weight_g or item.estimated_weight_g
        now = datetime.now(UTC)
        if memory is None:
            self.session.add(
                PersonalFoodMemory(
                    user_id=user_id,
                    normalized_detected_label=label,
                    confirmed_food_id=food_id,
                    location_context=location,
                    average_ai_weight_g=ai_weight,
                    average_confirmed_weight_g=confirmed_weight,
                    sample_count=1,
                    confidence=Decimal("0.7"),
                    last_seen_at=now,
                )
            )
            return
        count = Decimal(memory.sample_count)
        memory.average_ai_weight_g = (memory.average_ai_weight_g * count + ai_weight) / (count + 1)
        memory.average_confirmed_weight_g = (
            memory.average_confirmed_weight_g * count + confirmed_weight
        ) / (count + 1)
        memory.sample_count += 1
        memory.confidence = min(
            Decimal("0.99"), Decimal("0.7") + Decimal("0.03") * memory.sample_count
        )
        memory.last_seen_at = now

    async def _owned(self, user_id: UUID, analysis_id: UUID) -> MealAnalysisSession:
        analysis = await self.analyses.by_id(user_id, analysis_id)
        if analysis is None:
            raise AppError("analysis_not_found", "Meal analysis was not found.", 404)
        return analysis

    async def _editable(
        self, user_id: UUID, analysis_id: UUID, allow_failed: bool = False
    ) -> MealAnalysisSession:
        analysis = await self._owned(user_id, analysis_id)
        allowed = {"completed"} | ({"failed"} if allow_failed else set())
        if analysis.status not in allowed:
            raise AppError(
                "analysis_not_editable",
                "Only a completed draft can be edited.",
                409,
            )
        return analysis

    async def _visible_food(self, user_id: UUID, food_id: UUID) -> FoodItem:
        food = await self.foods.by_id(user_id, food_id)
        if food is None:
            raise AppError("food_not_found", "Food was not found.", 404)
        return food

    @staticmethod
    def _confidence_label(value: Decimal) -> str:
        if value >= Decimal("0.8"):
            return "high"
        if value >= Decimal("0.55"):
            return "medium"
        return "low"

    @classmethod
    def _read(cls, analysis: MealAnalysisSession) -> MealAnalysisRead:
        active = [item for item in analysis.items if item.deleted_at is None]
        items: list[MealAnalysisItemRead] = []
        for item in active:
            confidence = min(
                item.recognition_confidence,
                item.portion_confidence,
                item.match_confidence,
            )
            items.append(
                MealAnalysisItemRead(
                    id=item.id,
                    position=item.position,
                    detected_name=item.detected_name,
                    matched_food_id=item.matched_food_id,
                    matched_food_name=item.matched_food.name if item.matched_food else None,
                    match_type=item.match_type,
                    match_confidence=item.match_confidence,
                    recognition_confidence=item.recognition_confidence,
                    portion_confidence=item.portion_confidence,
                    confidence_label=cls._confidence_label(confidence),
                    estimated_weight_g=item.estimated_weight_g,
                    min_weight_g=item.min_weight_g,
                    max_weight_g=item.max_weight_g,
                    portion_description=item.portion_description,
                    cooking_method=item.cooking_method,
                    visible_components=item.visible_components,
                    possible_hidden_ingredients=item.possible_hidden_ingredients,
                    is_hidden_ingredient=item.is_hidden_ingredient,
                    user_modified=item.user_modified,
                    calories=item.calories,
                    protein=item.protein,
                    carbs=item.carbs,
                    fat=item.fat,
                    fiber=item.fiber,
                    min_calories=item.min_calories,
                    max_calories=item.max_calories,
                )
            )
        totals = MealAnalysisTotals(
            calories=sum((item.calories for item in active), ZERO),
            min_calories=sum((item.min_calories for item in active), ZERO),
            max_calories=sum((item.max_calories for item in active), ZERO),
            protein=sum((item.protein for item in active), ZERO),
            carbs=sum((item.carbs for item in active), ZERO),
            fat=sum((item.fat for item in active), ZERO),
            fiber=sum((item.fiber for item in active), ZERO),
        )
        return MealAnalysisRead(
            id=analysis.id,
            status=analysis.status,
            meal_type=analysis.meal_type,
            eaten_at=analysis.eaten_at,
            note=analysis.note,
            location_context=analysis.location_context,
            provider=analysis.provider,
            model=analysis.model,
            prompt_version=analysis.prompt_version,
            overall_confidence=analysis.overall_confidence,
            confidence_label=(
                cls._confidence_label(analysis.overall_confidence)
                if analysis.overall_confidence is not None
                else None
            ),
            warnings=analysis.warnings,
            error_code=analysis.error_code,
            error_message=analysis.error_message,
            reanalysis_count=analysis.reanalysis_count,
            expires_at=analysis.expires_at,
            confirmed_meal_id=analysis.confirmed_meal_id,
            items=items,
            totals=totals,
            created_at=analysis.created_at,
            updated_at=analysis.updated_at,
        )

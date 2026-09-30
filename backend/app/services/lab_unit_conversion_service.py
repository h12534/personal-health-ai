from decimal import ROUND_HALF_UP, Decimal

from app.core.errors import AppError


class LabUnitConversionService:
    @classmethod
    def convert(
        cls, normalized_name: str, value: Decimal, source_unit: str, target_unit: str
    ) -> Decimal:
        source = cls._unit(source_unit)
        target = cls._unit(target_unit)
        if source == target:
            return value
        key = normalized_name.upper()
        if key in {"FASTING_GLUCOSE"}:
            return cls._reciprocal(value, source, target, "mg/dl", "mmol/l", Decimal("18"))
        if key in {"TOTAL_CHOLESTEROL", "LDL_C", "HDL_C"}:
            return cls._reciprocal(value, source, target, "mg/dl", "mmol/l", Decimal("38.67"))
        if key == "TRIGLYCERIDES":
            return cls._reciprocal(value, source, target, "mg/dl", "mmol/l", Decimal("88.57"))
        if key == "CREATININE":
            return cls._reciprocal(value, source, target, "μmol/l", "mg/dl", Decimal("88.4"))
        if key == "URIC_ACID":
            return cls._reciprocal(value, source, target, "μmol/l", "mg/dl", Decimal("59.48"))
        if key == "HBA1C" and source == "mmol/mol" and target == "%":
            return (value / Decimal("10.929") + Decimal("2.15")).quantize(Decimal("0.01"))
        if key == "HBA1C" and source == "%" and target == "mmol/mol":
            return ((value - Decimal("2.15")) * Decimal("10.929")).quantize(Decimal("0.1"))
        raise AppError(
            "lab_unit_conversion_unsupported",
            f"Cannot convert {normalized_name} from {source_unit} to {target_unit}.",
            422,
        )

    @classmethod
    def _reciprocal(
        cls,
        value: Decimal,
        source: str,
        target: str,
        unit_a: str,
        unit_b: str,
        factor: Decimal,
    ) -> Decimal:
        if source == unit_a and target == unit_b:
            return (value / factor).quantize(Decimal("0.001"), rounding=ROUND_HALF_UP)
        if source == unit_b and target == unit_a:
            return (value * factor).quantize(Decimal("0.1"), rounding=ROUND_HALF_UP)
        raise AppError("lab_unit_conversion_unsupported", "Unsupported lab unit conversion.", 422)

    @staticmethod
    def _unit(value: str) -> str:
        return value.strip().lower().replace("umol", "μmol").replace(" ", "")

from datetime import date, datetime
from decimal import Decimal
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, model_validator

KnowledgeCategory = Literal[
    "fat_loss",
    "obesity",
    "muscle_gain",
    "nutrition",
    "protein",
    "carbohydrate",
    "fat",
    "fiber",
    "micronutrients",
    "hydration",
    "strength_training",
    "cardio",
    "sleep",
    "recovery",
    "insulin_resistance",
    "blood_glucose",
    "prediabetes",
    "type2_diabetes",
    "blood_pressure",
    "blood_lipids",
    "fatty_liver",
    "uric_acid",
    "metabolic_health",
    "body_weight_management",
    "behavior_change",
    "injury_prevention",
    "health_screening",
]

EvidenceLevel = Literal[
    "guideline",
    "systematic_review",
    "meta_analysis",
    "randomized_trial",
    "review",
    "observational",
    "expert_consensus",
    "general_reference",
]


class KnowledgeDocumentMetadata(BaseModel):
    title: str = Field(min_length=2, max_length=500)
    source: str = Field(min_length=2, max_length=120)
    source_url: str | None = Field(default=None, max_length=1000)
    publisher: str = Field(min_length=2, max_length=240)
    authors: list[str] = Field(default_factory=list, max_length=50)
    published_at: date | None = None
    source_updated_at: date | None = None
    document_version: str = Field(default="1", min_length=1, max_length=80)
    language: str = Field(default="zh-CN", min_length=2, max_length=16)
    category: KnowledgeCategory
    evidence_level: EvidenceLevel
    document_type: Literal[
        "guideline", "paper", "systematic_review", "reference", "consensus", "other"
    ]


class KnowledgeDocumentRead(BaseModel):
    id: UUID
    title: str
    source: str
    source_url: str | None
    publisher: str
    authors: list[str]
    published_at: date | None
    source_updated_at: date | None
    document_version: str
    language: str
    category: str
    evidence_level: str
    document_type: str
    active: bool
    archived: bool
    checksum: str
    content_hash: str
    ingested_at: datetime
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class KnowledgeChunkRead(BaseModel):
    id: UUID
    document_id: UUID
    chunk_index: int
    heading: str | None
    content: str
    token_count: int
    category: str
    chunk_metadata: dict[str, object]

    model_config = ConfigDict(from_attributes=True)


class KnowledgeIngestionRead(BaseModel):
    job_id: UUID
    document: KnowledgeDocumentRead
    chunk_count: int
    duplicate: bool


class KnowledgeStateUpdate(BaseModel):
    active: bool | None = None
    archived: bool | None = None


class RetrievalEvidence(BaseModel):
    document_id: UUID
    title: str
    publisher: str
    year: int | None
    chunk_id: UUID
    heading: str | None
    source_url: str | None
    excerpt: str
    score: float = Field(ge=0, le=1)
    category: str
    evidence_level: str


class KnowledgeSearchRequest(BaseModel):
    query: str = Field(min_length=2, max_length=2000)
    categories: list[KnowledgeCategory] = Field(default_factory=list, max_length=10)
    limit: int = Field(default=6, ge=1, le=20)


class KnowledgeSearchResponse(BaseModel):
    evidence: list[RetrievalEvidence]
    retrieval_method: str
    threshold: float


class LabOCRItemPatch(BaseModel):
    test_name: str | None = Field(default=None, min_length=1, max_length=200)
    normalized_name: str | None = Field(default=None, min_length=1, max_length=80)
    value_numeric: Decimal | None = None
    value_text: str | None = Field(default=None, max_length=240)
    unit: str | None = Field(default=None, max_length=40)
    reference_min: Decimal | None = None
    reference_max: Decimal | None = None
    reference_text: str | None = Field(default=None, max_length=240)

    @model_validator(mode="after")
    def validate_range(self) -> "LabOCRItemPatch":
        if (
            self.reference_min is not None
            and self.reference_max is not None
            and self.reference_min > self.reference_max
        ):
            raise ValueError("reference_min must not exceed reference_max")
        return self


class LabOCRItemRead(BaseModel):
    id: UUID
    page_number: int
    position: int
    test_code: str | None
    test_name: str
    normalized_name: str
    value_numeric: Decimal | None
    value_text: str | None
    unit: str | None
    reference_min: Decimal | None
    reference_max: Decimal | None
    reference_text: str | None
    flag: Literal["low", "normal", "high", "critical", "unknown"]
    category: str
    confidence: Decimal
    user_modified: bool

    model_config = ConfigDict(from_attributes=True)


class LabResultRead(BaseModel):
    id: UUID
    report_id: UUID
    test_code: str | None
    test_name: str
    normalized_name: str
    value_numeric: Decimal | None
    value_text: str | None
    unit: str | None
    reference_min: Decimal | None
    reference_max: Decimal | None
    reference_text: str | None
    flag: str
    category: str
    confidence: Decimal
    user_confirmed: bool

    model_config = ConfigDict(from_attributes=True)


class LabReportRead(BaseModel):
    id: UUID
    report_date: date
    hospital_name: str | None
    source_type: str
    original_filename: str
    ocr_status: str
    review_status: str
    retain_original: bool
    draft_items: list[LabOCRItemRead]
    results: list[LabResultRead]
    created_at: datetime
    updated_at: datetime


class LabConfirmRequest(BaseModel):
    item_ids: list[UUID] | None = Field(default=None, max_length=200)


class LabTrendPoint(BaseModel):
    report_id: UUID
    report_date: date
    value: Decimal
    unit: str
    flag: str
    reference_min: Decimal | None
    reference_max: Decimal | None


class LabTrendRead(BaseModel):
    normalized_name: str
    display_name: str
    canonical_unit: str
    points: list[LabTrendPoint]


class HealthCheckSuggestionRead(BaseModel):
    id: UUID
    report_id: UUID | None
    suggestion_type: str
    description: str
    suggested_after_days: int | None
    status: str

    model_config = ConfigDict(from_attributes=True)


class HealthChatRequest(BaseModel):
    message: str = Field(min_length=2, max_length=4000)
    conversation_id: UUID | None = None


class HealthSuggestedAction(BaseModel):
    type: Literal[
        "open_lab",
        "open_trend",
        "suggest_follow_up",
        "contact_clinician",
        "seek_urgent_care",
        "none",
    ]
    label: str
    target_id: str | None = None
    payload: dict[str, object] = Field(default_factory=dict)


class HealthChatResponse(BaseModel):
    conversation_id: UUID
    intent: str
    answer: str
    evidence: list[RetrievalEvidence]
    personal_context_used: list[str]
    risk_level: Literal["normal", "caution", "urgent"]
    medical_boundary: bool
    suggested_actions: list[HealthSuggestedAction]
    provider: str
    model: str
    retrieval_method: str
    rule_version: str = "health_ai_v1"

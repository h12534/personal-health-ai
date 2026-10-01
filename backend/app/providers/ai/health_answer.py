import json
from typing import Any

import httpx

from app.core.errors import AppError
from app.providers.ai.base import HealthAnswerProviderResponse


class MockHealthAnswerProvider:
    name = "mock"
    model = "mock-health-answer-v1"

    async def answer(
        self,
        message: str,
        intent: str,
        context: dict[str, Any],
        evidence: list[dict[str, Any]],
    ) -> HealthAnswerProviderResponse:
        del message
        if intent in {"daily_report", "weekly_report", "monthly_report"}:
            calories = context.get("average_calories")
            protein = context.get("average_protein_g")
            steps = context.get("average_steps")
            workouts = context.get("workouts_completed", 0)
            task_rate = context.get("task_completion_rate")
            parts = ["本期记录已完成汇总。"]
            if calories is not None:
                parts.append(f"平均热量约 {round(float(calories))} kcal。")
            if protein is not None:
                parts.append(f"平均蛋白质约 {round(float(protein))} g。")
            if steps is not None:
                parts.append(f"平均步数约 {round(float(steps))}。")
            if workouts:
                parts.append(f"共完成 {workouts} 次训练。")
            if task_rate is not None:
                parts.append(f"任务完成率约 {round(float(task_rate) * 100)}%。")
            parts.append("建议只选择一项最容易执行的改进继续观察，不因单日波动惩罚自己。")
            return HealthAnswerProviderResponse(
                answer="".join(parts), provider=self.name, model=self.model
            )
        if intent == "proactive_summary":
            trigger = str(context.get("trigger_type", "健康记录"))
            return HealthAnswerProviderResponse(
                answer=f"{trigger}出现了连续趋势，今天优先做一个温和、可执行的调整。",
                provider=self.name,
                model=self.model,
            )
        source = evidence[0] if evidence else None
        basis = (
            f"知识库中“{source['title']}”（{source['publisher']}）提供了相关背景。"
            if source
            else "当前知识库没有达到最低证据阈值的可靠来源。"
        )
        if intent == "lab_explanation":
            labs = context.get("lab_results") or []
            if labs:
                latest = labs[0]
                answer = (
                    f"{latest['test_name']} 当前记录为 {latest.get('value')} "
                    f"{latest.get('unit') or ''}，报告标记为 {latest.get('flag')}。"
                    "这只能说明该次报告中的数值和参考范围，不能单独确认疾病诊断。"
                    f"{basis} 如持续异常或伴随症状，建议携带原报告与医生讨论复查时间。"
                )
            else:
                answer = f"目前没有已确认的对应体检指标。{basis}请先确认 OCR 草稿或补充正式报告。"
        elif intent == "weight_health":
            trend = context.get("weight_trend") or {}
            answer = (
                f"先看 7–28 天趋势，不用把单日变化直接解释成脂肪变化。"
                f"你的趋势记录显示：{trend.get('note', '当前数据不足。')}{basis}"
            )
        elif intent == "symptom_question":
            answer = (
                f"仅凭文字或照片不能确认具体疾病。{basis}可以关注持续时间、变化、伴随症状，"
                "并由医生结合查体和必要检查判断。"
            )
        else:
            answer = f"我会把可靠知识来源与最少必要的个人数据分开说明。{basis}"
        return HealthAnswerProviderResponse(answer=answer, provider=self.name, model=self.model)


class OpenAICompatibleHealthAnswerProvider:
    name = "openai_compatible"

    def __init__(self, *, base_url: str, api_key: str, model: str, timeout_seconds: int) -> None:
        self.base_url = base_url.rstrip("/")
        self.api_key = api_key
        self.model = model
        self.timeout_seconds = timeout_seconds

    async def answer(
        self,
        message: str,
        intent: str,
        context: dict[str, Any],
        evidence: list[dict[str, Any]],
    ) -> HealthAnswerProviderResponse:
        instructions = (
            "你是基于证据的个人健康解释助手。只能使用提供的 evidence 和 personal_context。"
            "不得诊断、不得指导停药或修改处方、不得制造焦虑、不得声称相关性等于因果。"
            "如果 evidence 为空，明确说知识库依据不足。回答使用中文，不虚构来源。"
        )
        try:
            async with httpx.AsyncClient(timeout=self.timeout_seconds) as client:
                response = await client.post(
                    f"{self.base_url}/chat/completions",
                    headers={"Authorization": f"Bearer {self.api_key}"},
                    json={
                        "model": self.model,
                        "temperature": 0.1,
                        "messages": [
                            {"role": "system", "content": instructions},
                            {
                                "role": "user",
                                "content": json.dumps(
                                    {
                                        "intent": intent,
                                        "question": message,
                                        "personal_context": context,
                                        "evidence": evidence,
                                    },
                                    ensure_ascii=False,
                                    default=str,
                                ),
                            },
                        ],
                    },
                )
                response.raise_for_status()
                payload = response.json()
                answer = str(payload["choices"][0]["message"]["content"])
                usage = payload.get("usage") or {}
        except (httpx.HTTPError, KeyError, TypeError, ValueError) as exc:
            raise AppError(
                "health_answer_provider_error", "Health answer provider failed.", 502
            ) from exc
        return HealthAnswerProviderResponse(
            answer=answer,
            provider=self.name,
            model=self.model,
            input_tokens=usage.get("prompt_tokens"),
            output_tokens=usage.get("completion_tokens"),
        )

"""Cost calculation for AI assistant telemetry.

This module provides cost calculation based on provider pricing tables.
Part of feature 125-tracing-parity-codex for multi-CLI tracing parity.
"""

from typing import Optional

from .models import (
    DEFAULT_PRICING,
    PROVIDER_PRICING,
    Provider,
)


def calculate_cost(
    provider: Provider,
    model: Optional[str],
    input_tokens: int,
    output_tokens: int,
) -> tuple[float, bool]:
    """Calculate cost in USD for token usage.

    Args:
        provider: AI service provider
        model: Model name (e.g., "gpt-4o", "claude-sonnet-4")
        input_tokens: Number of input tokens
        output_tokens: Number of output tokens

    Returns:
        Tuple of (cost_usd, is_estimated).
        is_estimated is True if the model was not found in pricing table.
    """
    # Get pricing for provider
    provider_pricing = PROVIDER_PRICING.get(provider, {})

    # Try to find model pricing
    pricing = None
    is_estimated = False

    if model:
        # Try exact match first
        pricing = provider_pricing.get(model)

        # Try prefix match (e.g., "gpt-4o-2024-11-20" matches "gpt-4o")
        if not pricing:
            for model_prefix, price in provider_pricing.items():
                if model.startswith(model_prefix):
                    pricing = price
                    break

        # Try case-insensitive match
        if not pricing:
            model_lower = model.lower()
            for model_name, price in provider_pricing.items():
                if model_name.lower() == model_lower:
                    pricing = price
                    break

    # Fall back to default pricing if model not found
    if not pricing:
        pricing = DEFAULT_PRICING
        is_estimated = True

    input_price, output_price = pricing

    # Calculate cost (prices are per 1M tokens)
    input_cost = (input_tokens / 1_000_000) * input_price
    output_cost = (output_tokens / 1_000_000) * output_price
    total_cost = input_cost + output_cost

    return total_cost, is_estimated


def get_model_pricing(
    provider: Provider,
    model: str,
) -> tuple[float, float, bool]:
    """Get pricing for a specific model.

    Args:
        provider: AI service provider
        model: Model name

    Returns:
        Tuple of (input_price, output_price, is_default).
        Prices are per 1M tokens.
    """
    provider_pricing = PROVIDER_PRICING.get(provider, {})

    if model in provider_pricing:
        input_price, output_price = provider_pricing[model]
        return input_price, output_price, False

    # Try prefix match
    for model_prefix, (input_price, output_price) in provider_pricing.items():
        if model.startswith(model_prefix):
            return input_price, output_price, False

    return DEFAULT_PRICING[0], DEFAULT_PRICING[1], True

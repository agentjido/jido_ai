---
name: unit-converter
description: Converts between common units of measurement including temperature, distance, and weight.
license: Apache-2.0
allowed-tools: convert_temperature convert_distance convert_weight
metadata:
  author: jido-examples
  version: "1.0"
tags:
  - conversion
  - units
  - utility
---

# Unit Converter Skill

## Purpose
Use this skill when users ask about unit conversions for temperature, distance, or weight.

## Available Operations

### Temperature
- `convert_temperature(value, from, to)` - Convert between Celsius, Fahrenheit, and Kelvin
- Common conversions: C↔F, C↔K, F↔K

### Distance  
- `convert_distance(value, from, to)` - Convert between metric and imperial
- Supports: meters, kilometers, miles, feet, inches, yards

### Weight
- `convert_weight(value, from, to)` - Convert between weight units
- Supports: kilograms, pounds, ounces, grams, stones

## Workflow

1. **Identify the conversion type** (temperature, distance, or weight)
2. **Extract the value and units** from the user's request
3. **Call the appropriate conversion tool** with correct parameters
4. **Present the result** with both original and converted values

## Examples

User: "What is 100°F in Celsius?"
→ convert_temperature(100, "fahrenheit", "celsius")
→ "100°F = 37.78°C"

User: "How many kilometers is a marathon?"
→ convert_distance(26.2, "miles", "kilometers")  
→ "A marathon (26.2 miles) = 42.16 km"

User: "Convert 150 pounds to kilograms"
→ convert_weight(150, "pounds", "kilograms")
→ "150 lbs = 68.04 kg"

## Best Practices
- Always show both the original and converted values
- Round to 2 decimal places for readability
- Include the unit abbreviations for clarity

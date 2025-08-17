# API Response Fixtures

This directory contains JSON fixtures representing actual API responses from the IBKR Web API.

## Purpose

These fixtures are used for:
- Testing API response parsing and transformation
- Developing and testing new features without making live API calls
- Ensuring consistent test data across different environments
- Documenting the expected structure of API responses

## Organization

- `accounts/` - Account-related API responses
- `portfolio/` - Portfolio and position data responses
- `transactions/` - Transaction history responses
- `authentication/` - Authentication and session-related responses

## Usage

These fixtures should be loaded in tests using the fixture helper methods. Never modify these files manually - they should represent actual API responses.

## Security

Ensure all account IDs, personal information, and sensitive data are anonymized or use demo/sandbox data only.
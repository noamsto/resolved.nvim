# Security

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| main    | :white_check_mark: |
| < 1.0   | :x:                |

## Reporting a Vulnerability

If you discover a security vulnerability, please open a security advisory on GitHub.

## Security Measures

### URL Validation

All GitHub URLs are validated before processing to prevent:
- Path traversal attacks (e.g., `../../../etc/passwd`)
- Injection attacks via malformed repository/owner names
- Malformed URLs with invalid characters

The validation ensures:
- No leading or trailing dots in owner/repo names
- No consecutive dots (prevents `..` path traversal)
- Only valid characters (alphanumeric, hyphens, dots)

### Command Execution

All external commands (`gh` CLI) are executed via `vim.system` with:
- Proper argument array separation (no shell injection)
- Timeout protection (30 second limit for git operations)
- Async execution (non-blocking)
- Stderr/stdout separation for proper error handling

### Buffer Safety

All buffer operations are wrapped in:
- Validity checks before access
- `pcall` protection for async operations
- Proper cleanup on buffer deletion
- Error logging instead of crashing

### Rate Limiting

The plugin respects GitHub API rate limits via:
- Local caching with TTL (default 5 minutes)
- Debounced scanning (default 500ms)
- Batch fetching to minimize API calls

## Past Vulnerabilities

None reported yet (plugin in initial development).

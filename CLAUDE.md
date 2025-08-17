# Claude AI Assistant Notes

> **For overall environment context, see: `/home/claude/workspace/AINotes/AINotes.md`**

## Project Overview
[Project description to be added]

## Recent Work & Changes
_This section is updated by Claude during each session_

### Session: 2025-08-17
- Initial CLAUDE.md created
- **SECURITY FIX**: Moved certificates out of git repository
  - Certificates relocated to `/home/claude/workspace/data/traefik-certs/`
  - Created symlink from `certs` → `../data/traefik-certs`
  - Added `certs` to .gitignore
  - Private keys should NEVER be in version control

## Known Issues & TODOs
- None currently documented

## Important Notes
- Owner: WebSurfinMurf
- File ownership should be: node:node
- **Certificates**: Stored in `/home/claude/workspace/data/traefik-certs/` (symlinked)
- **Security**: Private keys excluded from git via .gitignore

## Dependencies
[List any project dependencies or related services]

## Common Commands
[List frequently used commands for this project]
### Session: 2025-08-17 (Session 3)
- Added comprehensive .gitignore to prevent sensitive file commits
- acme.json removed from git history for security
- deploy.sh properly handles acme.json creation with 600 permissions

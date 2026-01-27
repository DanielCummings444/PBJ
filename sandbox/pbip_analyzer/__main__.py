"""Allow running as `python -m pbip_analyzer` to start the MCP server,
or `python -m pbip_analyzer.cli <path>` for standalone CLI usage.
"""

import asyncio
from pbip_analyzer.server import main

asyncio.run(main())

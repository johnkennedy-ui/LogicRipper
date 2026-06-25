Integration tests that need live Azure access are intentionally not enabled by
default. The MVP unit suite uses redacted workflow fixtures and validates the
offline rip, sanitise, store, bind and package paths.

# Changelog

## v0.1.0

- First tagged source release with an explicit v0.1.x CLI compatibility policy.
- Check binary stdin/stdout, normal exit status and optional streamed stderr.
- Retain explicit numeric configuration and bounded escaped stdout differences,
  with LCS default and explicit sparse comparison from goose-diff v0.1.0.
- Preserve direct-child cancellation, cleanup and exceptional ownership recovery.
- Document source installation, platform requirements and resource limits.

Implementation and vendor bytes are unchanged from 91de39c. No new performance
or binary-portability guarantee is made.

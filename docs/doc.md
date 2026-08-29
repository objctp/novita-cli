# nv doc
Read the manual embedded in nv's own source comments.
`nv doc` is the reference surface: every user-facing command and verb carries
a documentation block in its source file, and this command renders it. Where
`--help` is a terse reminder of the flags, `nv doc` is the page you read to
learn a command — arguments, defaults, constraints, caveats, examples, and the
API call each verb makes. Library internals are never documented here.

```
nv doc [command] [verb] [sub-verb]
```

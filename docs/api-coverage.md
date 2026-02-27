# API Coverage

NeonRaw re-exports C APIs from `CNeon` and adds Swift-safe handle wrappers.

## Public headers covered
- [x] `ne_207.h`
- [x] `ne_acl.h`
- [x] `ne_acl3744.h`
- [x] `ne_alloc.h`
- [x] `ne_auth.h`
- [x] `ne_basic.h`
- [x] `ne_compress.h`
- [x] `ne_dates.h`
- [x] `ne_i18n.h`
- [x] `ne_locks.h`
- [x] `ne_md5.h`
- [x] `ne_pkcs11.h`
- [x] `ne_props.h`
- [x] `ne_redirect.h`
- [x] `ne_request.h`
- [x] `ne_session.h`
- [x] `ne_socket.h`
- [x] `ne_ssl.h`
- [x] `ne_string.h`
- [x] `ne_uri.h`
- [x] `ne_utils.h`
- [x] `ne_xml.h`
- [x] `ne_xmlreq.h`

Notes:
- `ne_acl3744.h` is imported directly through `CNeon`.
- `ne_acl.h` conflicts with `ne_acl3744.h` at C enum/type level, so legacy ACL is exposed via `CNeonShim` compatibility wrappers (`nk_acl_set_legacy`) and deprecated Swift API (`deprecatedSetACL`).

## Excluded private headers
- [x] `ne_internal.h`
- [x] `ne_private.h`
- [x] `ne_privssl.h`

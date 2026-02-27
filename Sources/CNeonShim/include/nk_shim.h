#ifndef NK_SHIM_H
#define NK_SHIM_H

#include <stddef.h>
#include "../../CNeon/include/ne_auth.h"
#include "../../CNeon/include/ne_props.h"
#include "../../CNeon/include/ne_request.h"
#include "../../CNeon/include/ne_session.h"
#include "../../CNeon/include/ne_socket.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct nk_auth_context nk_auth_context;

typedef struct {
    int apply;
    int type;
    const char *principal;
    int read;
    int read_acl;
    int write;
    int write_acl;
    int read_cuprivset;
} nk_acl_legacy_entry;

typedef struct {
    char *href;
    char *path;
    char *display_name;
    char *etag;
    char *content_type;
    long long content_length;
    char *last_modified;
    int is_collection;
    int status_code;
} nk_prop_item;

typedef struct {
    nk_prop_item *items;
    size_t count;
} nk_prop_list;

typedef struct {
    int ne_code;
    int status_code;
    int status_class;
    char *reason;
    char *body;
    size_t body_len;
    char *error;
    char **header_names;
    char **header_values;
    size_t header_count;
} nk_response;

int nk_global_init(void);
void nk_global_shutdown(void);

nk_auth_context *nk_auth_context_create(const char *username, const char *password);
void nk_auth_context_destroy(nk_auth_context *ctx);
void nk_session_set_server_auth(ne_session *sess, nk_auth_context *ctx);
int nk_acl_set_legacy(
    ne_session *sess,
    const char *uri,
    const nk_acl_legacy_entry entries[],
    int numentries
);

int nk_collect_propfind(ne_session *sess, const char *path, int depth, nk_prop_list *out_list);
void nk_prop_list_free(nk_prop_list *list);

int nk_dispatch_request(
    ne_session *sess,
    const char *method,
    const char *target,
    const char *body,
    size_t body_len,
    const char *const *header_names,
    const char *const *header_values,
    size_t header_count,
    nk_response *out_response
);
void nk_response_free(nk_response *response);
void nk_string_free(char *string);

#ifdef __cplusplus
}
#endif

#endif

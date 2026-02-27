#include "nk_shim.h"
#include <ne_acl.h>

#include <pthread.h>
#include <stdlib.h>
#include <string.h>

struct nk_auth_context {
    char *username;
    char *password;
};

static pthread_mutex_t nk_global_lock = PTHREAD_MUTEX_INITIALIZER;
static int nk_global_count = 0;

static char *nk_strdup(const char *value) {
    if (value == NULL) {
        return NULL;
    }

    size_t len = strlen(value);
    char *copy = malloc(len + 1);
    if (copy == NULL) {
        return NULL;
    }

    memcpy(copy, value, len + 1);
    return copy;
}

int nk_global_init(void) {
    int ret = 0;
    pthread_mutex_lock(&nk_global_lock);

    if (nk_global_count == 0) {
        ret = ne_sock_init();
    }

    if (ret == 0) {
        nk_global_count += 1;
    }

    pthread_mutex_unlock(&nk_global_lock);
    return ret;
}

void nk_global_shutdown(void) {
    pthread_mutex_lock(&nk_global_lock);

    if (nk_global_count > 0) {
        nk_global_count -= 1;
        if (nk_global_count == 0) {
            ne_sock_exit();
        }
    }

    pthread_mutex_unlock(&nk_global_lock);
}

nk_auth_context *nk_auth_context_create(const char *username, const char *password) {
    nk_auth_context *ctx = calloc(1, sizeof(nk_auth_context));
    if (ctx == NULL) {
        return NULL;
    }

    ctx->username = nk_strdup(username);
    ctx->password = nk_strdup(password);

    if (ctx->username == NULL || ctx->password == NULL) {
        nk_auth_context_destroy(ctx);
        return NULL;
    }

    return ctx;
}

void nk_auth_context_destroy(nk_auth_context *ctx) {
    if (ctx == NULL) {
        return;
    }

    free(ctx->username);
    free(ctx->password);
    free(ctx);
}

static int nk_auth_callback(void *userdata, const char *realm, int attempt, char *username, char *password) {
    (void)realm;
    nk_auth_context *ctx = userdata;

    if (ctx == NULL || attempt > 2) {
        return 1;
    }

    strncpy(username, ctx->username, NE_ABUFSIZ - 1);
    username[NE_ABUFSIZ - 1] = '\0';

    strncpy(password, ctx->password, NE_ABUFSIZ - 1);
    password[NE_ABUFSIZ - 1] = '\0';

    return 0;
}

void nk_session_set_server_auth(ne_session *sess, nk_auth_context *ctx) {
    ne_set_server_auth(sess, nk_auth_callback, ctx);
}

int nk_acl_set_legacy(
    ne_session *sess,
    const char *uri,
    const nk_acl_legacy_entry entries[],
    int numentries
) {
    int idx;
    int ret;
    ne_acl_entry *buffer;

    if (numentries <= 0) {
        return ne_acl_set(sess, uri, NULL, 0);
    }

    buffer = calloc((size_t)numentries, sizeof(ne_acl_entry));
    if (buffer == NULL) {
        return NE_ERROR;
    }

    for (idx = 0; idx < numentries; idx += 1) {
        const nk_acl_legacy_entry *src = &entries[idx];
        ne_acl_entry *dst = &buffer[idx];

        switch (src->apply) {
        case 0:
            dst->apply = ne_acl_href;
            break;
        case 1:
            dst->apply = ne_acl_property;
            break;
        case 2:
        default:
            dst->apply = ne_acl_all;
            break;
        }

        dst->type = src->type == 0 ? ne_acl_grant : ne_acl_deny;
        dst->principal = nk_strdup(src->principal);
        dst->read = src->read;
        dst->read_acl = src->read_acl;
        dst->write = src->write;
        dst->write_acl = src->write_acl;
        dst->read_cuprivset = src->read_cuprivset;
    }

    ret = ne_acl_set(sess, uri, buffer, numentries);

    for (idx = 0; idx < numentries; idx += 1) {
        free(buffer[idx].principal);
    }
    free(buffer);

    return ret;
}

typedef struct {
    char *data;
    size_t length;
    size_t capacity;
    int has_error;
} nk_buffer;

static int nk_buffer_append(nk_buffer *buffer, const char *data, size_t len) {
    if (len == 0) {
        return 0;
    }

    if (buffer->length + len + 1 > buffer->capacity) {
        size_t new_capacity = buffer->capacity == 0 ? 4096 : buffer->capacity;
        while (new_capacity < buffer->length + len + 1) {
            new_capacity *= 2;
        }

        char *new_data = realloc(buffer->data, new_capacity);
        if (new_data == NULL) {
            buffer->has_error = 1;
            return -1;
        }

        buffer->data = new_data;
        buffer->capacity = new_capacity;
    }

    memcpy(buffer->data + buffer->length, data, len);
    buffer->length += len;
    buffer->data[buffer->length] = '\0';
    return 0;
}

static int nk_reader_callback(void *userdata, const char *buf, size_t len) {
    nk_buffer *buffer = userdata;

    if (buffer->has_error) {
        return -1;
    }

    return nk_buffer_append(buffer, buf, len);
}

static void nk_clear_response(nk_response *response) {
    memset(response, 0, sizeof(*response));
}

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
) {
    nk_buffer buffer = {0};
    int code;
    ne_request *req;
    size_t idx;

    nk_clear_response(out_response);

    req = ne_request_create(sess, method, target);
    if (req == NULL) {
        out_response->ne_code = NE_ERROR;
        out_response->error = nk_strdup("failed to create request");
        return NE_ERROR;
    }

    if (body != NULL && body_len > 0) {
        ne_set_request_body_buffer(req, body, body_len);
    }

    for (idx = 0; idx < header_count; idx += 1) {
        if (header_names[idx] != NULL && header_values[idx] != NULL) {
            ne_add_request_header(req, header_names[idx], header_values[idx]);
        }
    }

    ne_add_response_body_reader(req, ne_accept_always, nk_reader_callback, &buffer);
    code = ne_request_dispatch(req);

    out_response->ne_code = code;

    if (buffer.data != NULL) {
        out_response->body = buffer.data;
        out_response->body_len = buffer.length;
    }

    {
        const ne_status *status = ne_get_status(req);
        if (status != NULL) {
            out_response->status_code = status->code;
            out_response->status_class = status->klass;
            out_response->reason = nk_strdup(status->reason_phrase);
        }
    }

    {
        const char *name;
        const char *value;
        void *cursor = NULL;
        while ((cursor = ne_response_header_iterate(req, cursor, &name, &value)) != NULL) {
            size_t pos = out_response->header_count;
            char **names;
            char **values;

            names = realloc(out_response->header_names, sizeof(char *) * (pos + 1));
            values = realloc(out_response->header_values, sizeof(char *) * (pos + 1));
            if (names == NULL || values == NULL) {
                free(names);
                free(values);
                break;
            }

            out_response->header_names = names;
            out_response->header_values = values;
            out_response->header_names[pos] = nk_strdup(name);
            out_response->header_values[pos] = nk_strdup(value);
            out_response->header_count = pos + 1;
        }
    }

    if (code != NE_OK) {
        out_response->error = nk_strdup(ne_get_error(sess));
    }

    ne_request_destroy(req);
    return code;
}

void nk_response_free(nk_response *response) {
    size_t idx;

    if (response == NULL) {
        return;
    }

    free(response->reason);
    free(response->body);
    free(response->error);

    for (idx = 0; idx < response->header_count; idx += 1) {
        free(response->header_names[idx]);
        free(response->header_values[idx]);
    }

    free(response->header_names);
    free(response->header_values);

    nk_clear_response(response);
}

static const ne_propname nk_props[] = {
    {"DAV:", "displayname"},
    {"DAV:", "getetag"},
    {"DAV:", "getcontenttype"},
    {"DAV:", "getcontentlength"},
    {"DAV:", "getlastmodified"},
    {"DAV:", "resourcetype"},
    {NULL, NULL}
};

typedef struct {
    nk_prop_item *items;
    size_t count;
} nk_prop_builder;

static void nk_prop_callback(void *userdata, const ne_uri *uri, const ne_prop_result_set *results) {
    nk_prop_builder *builder = userdata;
    nk_prop_item item = {0};
    const char *value;
    const ne_status *status;

    nk_prop_item *items = realloc(builder->items, sizeof(nk_prop_item) * (builder->count + 1));
    if (items == NULL) {
        return;
    }

    builder->items = items;

    item.href = nk_strdup(uri->path);
    item.path = nk_strdup(uri->path);

    value = ne_propset_value(results, &nk_props[0]);
    item.display_name = nk_strdup(value);

    value = ne_propset_value(results, &nk_props[1]);
    item.etag = nk_strdup(value);

    value = ne_propset_value(results, &nk_props[2]);
    item.content_type = nk_strdup(value);

    value = ne_propset_value(results, &nk_props[3]);
    if (value != NULL) {
        char *endptr = NULL;
        item.content_length = strtoll(value, &endptr, 10);
        if (endptr == value) {
            item.content_length = -1;
        }
    } else {
        item.content_length = -1;
    }

    value = ne_propset_value(results, &nk_props[4]);
    item.last_modified = nk_strdup(value);

    value = ne_propset_value(results, &nk_props[5]);
    item.is_collection = value != NULL && strstr(value, "collection") != NULL;

    status = ne_propset_status(results, &nk_props[0]);
    item.status_code = status == NULL ? 0 : status->code;

    builder->items[builder->count] = item;
    builder->count += 1;
}

int nk_collect_propfind(ne_session *sess, const char *path, int depth, nk_prop_list *out_list) {
    nk_prop_builder builder = {0};
    int ret;

    out_list->items = NULL;
    out_list->count = 0;

    ret = ne_simple_propfind(sess, path, depth, nk_props, nk_prop_callback, &builder);
    if (ret != NE_OK) {
        nk_prop_list temp;
        temp.items = builder.items;
        temp.count = builder.count;
        nk_prop_list_free(&temp);
        return ret;
    }

    out_list->items = builder.items;
    out_list->count = builder.count;
    return NE_OK;
}

void nk_prop_list_free(nk_prop_list *list) {
    size_t idx;

    if (list == NULL || list->items == NULL) {
        return;
    }

    for (idx = 0; idx < list->count; idx += 1) {
        free(list->items[idx].href);
        free(list->items[idx].path);
        free(list->items[idx].display_name);
        free(list->items[idx].etag);
        free(list->items[idx].content_type);
        free(list->items[idx].last_modified);
    }

    free(list->items);
    list->items = NULL;
    list->count = 0;
}

void nk_string_free(char *string) {
    free(string);
}

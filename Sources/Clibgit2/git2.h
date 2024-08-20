#pragma once
#include <git2.h>
#include <git2/sys/errors.h>
#include <git2/sys/transport.h>

/* Wrapper structs to allow Swift to pass a context pointer containing a class */
struct git_smart_subtransport_swift {
    git_smart_subtransport parent;
    git_transport *owner;
    void *context;
};

struct git_smart_subtransport_stream_swift {
    git_smart_subtransport_stream parent;
    void *context;
};

static git_status_options git_status_options_init_value = GIT_STATUS_OPTIONS_INIT;

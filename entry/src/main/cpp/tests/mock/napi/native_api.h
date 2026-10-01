#pragma once
// Deliberately limited host model. This is not the HarmonyOS SDK or an ABI shim.
#include <cstddef>
#include <cstdint>
struct MockEnv;
struct MockValue;
struct MockInfo;
struct MockDeferred;
struct MockWork;
using napi_env = MockEnv*;
using napi_value = MockValue*;
using napi_callback_info = MockInfo*;
using napi_deferred = MockDeferred*;
using napi_async_work = MockWork*;
enum napi_status { napi_ok, napi_generic_failure };
enum napi_valuetype { napi_undefined, napi_null, napi_boolean, napi_number, napi_string, napi_object };
enum napi_property_attributes { napi_default };
using napi_callback = napi_value (*)(napi_env, napi_callback_info);
using napi_async_execute_callback = void (*)(napi_env, void*);
using napi_async_complete_callback = void (*)(napi_env, napi_status, void*);
struct napi_property_descriptor {
    const char* utf8name;
    napi_value name;
    napi_callback method;
    napi_callback getter;
    napi_callback setter;
    napi_value value;
    napi_property_attributes attributes;
    void* data;
};
napi_status napi_create_string_utf8(napi_env, const char*, size_t, napi_value*);
napi_status napi_create_object(napi_env, napi_value*);
napi_status napi_create_array(napi_env, napi_value*);
napi_status napi_create_double(napi_env, double, napi_value*);
napi_status napi_get_boolean(napi_env, bool, napi_value*);
napi_status napi_set_named_property(napi_env, napi_value, const char*, napi_value);
napi_status napi_set_element(napi_env, napi_value, std::uint32_t, napi_value);
napi_status napi_has_named_property(napi_env, napi_value, const char*, bool*);
napi_status napi_get_named_property(napi_env, napi_value, const char*, napi_value*);
napi_status napi_get_cb_info(napi_env, napi_callback_info, size_t*, napi_value*, napi_value*, void**);
napi_status napi_typeof(napi_env, napi_value, napi_valuetype*);
napi_status napi_get_null(napi_env, napi_value*);
napi_status napi_get_undefined(napi_env, napi_value*);
napi_status napi_strict_equals(napi_env, napi_value, napi_value, bool*);
napi_status napi_is_array(napi_env, napi_value, bool*);
napi_status napi_get_value_string_utf8(napi_env, napi_value, char*, size_t, size_t*);
napi_status napi_get_value_double(napi_env, napi_value, double*);
napi_status napi_create_error(napi_env, napi_value, napi_value, napi_value*);
napi_status napi_throw(napi_env, napi_value);
napi_status napi_throw_error(napi_env, const char*, const char*);
napi_status napi_is_exception_pending(napi_env, bool*);
napi_status napi_get_and_clear_last_exception(napi_env, napi_value*);
napi_status napi_create_promise(napi_env, napi_deferred*, napi_value*);
napi_status napi_create_async_work(napi_env, napi_value, napi_value, napi_async_execute_callback,
    napi_async_complete_callback, void*, napi_async_work*);
napi_status napi_queue_async_work(napi_env, napi_async_work);
napi_status napi_delete_async_work(napi_env, napi_async_work);
napi_status napi_resolve_deferred(napi_env, napi_deferred, napi_value);
napi_status napi_reject_deferred(napi_env, napi_deferred, napi_value);
napi_status napi_define_properties(napi_env, napi_value, size_t, const napi_property_descriptor*);

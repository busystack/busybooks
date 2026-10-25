// Native book-content boundary. Flutter owns all application chrome and actions.
#include "reader_host.h"
#include "reader_surface.h"
#include "reader_popover.h"
#include "reading_font_channel.h"
#include "../../native/reader_action_limits.h"
#include <webkit2/webkit2.h>
#include <cstring>
#include <string>
#include <algorithm>

struct BusyBooksReaderHost {
  BusyBooksReaderSurface* surface;
  ReaderPopover* popover = nullptr;
  GtkWidget* chrome = nullptr;
  WebKitWebView* web = nullptr;
  WebKitWebContext* context;
  FlMethodChannel* channel;
  FlMethodChannel* fonts;
  std::string assets;
  std::string publication;
  std::string cache_directory;
  std::string session;
};
static void emit(BusyBooksReaderHost* host, const char* json, std::size_t limit = 1048576) {
  if (!host->channel || !json) return;
  if (strlen(json) > limit) {
    const std::string error="{\"type\":\"bridgeError\",\"session\":\""+host->session+"\",\"direction\":\"event\",\"message\":\"Reader bridge frame limit exceeded\"}";
    emit(host,error.c_str());
    return;
  }
  g_autoptr(FlValue) arg = fl_value_new_string(json);
  fl_method_channel_invoke_method(host->channel, "event", arg, nullptr, nullptr, nullptr);
}
static void message(WebKitUserContentManager*, WebKitJavascriptResult* result, gpointer data) {
  auto* value = webkit_javascript_result_get_js_value(result);
  if (!jsc_value_is_string(value)) return;
  g_autofree char* json = jsc_value_to_string(value);
  emit(static_cast<BusyBooksReaderHost*>(data), json);
}
static void reader_error(BusyBooksReaderHost* h, const char* message) {
  if(h->session.empty())return;
  g_autoptr(FlValue) value=fl_value_new_map();
  fl_value_set_string_take(value,"type",fl_value_new_string("error"));
  fl_value_set_string_take(value,"session",fl_value_new_string(h->session.c_str()));
  fl_value_set_string_take(value,"message",fl_value_new_string(message));
  g_autoptr(FlJsonMessageCodec) codec=fl_json_message_codec_new();
  g_autoptr(GBytes) bytes=fl_message_codec_encode_message(FL_MESSAGE_CODEC(codec),value,nullptr);
  if(bytes){gsize length=0;const auto* data=static_cast<const char*>(g_bytes_get_data(bytes,&length));emit(h,std::string(data,length).c_str());}
}
static gboolean load_failed(WebKitWebView*,WebKitLoadEvent,const char* uri,GError* error,gpointer data) {
  auto* h=static_cast<BusyBooksReaderHost*>(data);
  if(h->session.empty()||!uri||std::string(uri).find("?session="+h->session+"&")==std::string::npos||g_error_matches(error,WEBKIT_NETWORK_ERROR,WEBKIT_NETWORK_ERROR_CANCELLED))return FALSE;
  reader_error(h,error->message);return TRUE;
}
static void process_terminated(WebKitWebView*,WebKitWebProcessTerminationReason reason,gpointer data) {
  auto* h=static_cast<BusyBooksReaderHost*>(data);
  const auto message="Reader process terminated ("+std::to_string(reason)+"). Reopen the book.";
  reader_error(h,message.c_str());
}
static void scheme(WebKitURISchemeRequest* request, gpointer data) {
  auto* h = static_cast<BusyBooksReaderHost*>(data);
  const char* raw = webkit_uri_scheme_request_get_path(request);
  g_autofree char* decoded = g_uri_unescape_string(raw, nullptr);
  std::string rel = decoded ? decoded : "";
  if (rel.empty() || rel.find("..") != std::string::npos || rel.find('\\') != std::string::npos) {
    g_autoptr(GError) err = g_error_new_literal(G_IO_ERROR, G_IO_ERROR_PERMISSION_DENIED, "Invalid reader resource");
    webkit_uri_scheme_request_finish_error(request, err); return;
  }
  std::string path;
  if (rel == "/publication") path=h->publication;
  else if(rel=="/book-index"||rel.rfind("/book/",0)==0){
    if(rel!="/book-index") {
      auto resource=rel.substr(6);
      if(resource.size()!=64||!std::all_of(resource.begin(),resource.end(),[](char c){return (c>='0'&&c<='9')||(c>='a'&&c<='f');})) {
        g_autoptr(GError) error=g_error_new_literal(G_IO_ERROR,G_IO_ERROR_PERMISSION_DENIED,"Invalid reader resource hash");
        webkit_uri_scheme_request_finish_error(request,error);return;
      }
    }
    path=h->cache_directory+(rel=="/book-index"?".json":"/"+rel.substr(6));
  } else path=h->assets+rel;
  g_autoptr(GFile) file = g_file_new_for_path(path.c_str());
  g_autoptr(GError) error = nullptr;
  GFileInputStream* stream = g_file_read(file, nullptr, &error);
  if (!stream) { webkit_uri_scheme_request_finish_error(request, error); return; }
  const char* mime = "application/octet-stream";
  if (g_str_has_suffix(path.c_str(), ".js") || g_str_has_suffix(path.c_str(), ".mjs")) mime = "text/javascript";
  else if (g_str_has_suffix(path.c_str(), ".html")) mime = "text/html";
  else if (g_str_has_suffix(path.c_str(), ".css")) mime = "text/css";
  else if (g_str_has_suffix(path.c_str(), ".json")) mime = "application/json";
  else if (g_str_has_suffix(path.c_str(), ".wasm")) mime = "application/wasm";
  webkit_uri_scheme_request_finish(request, G_INPUT_STREAM(stream), -1, mime);
  g_object_unref(stream);
}
static gboolean policy(WebKitWebView*, WebKitPolicyDecision* decision, WebKitPolicyDecisionType type, gpointer) {
  if (type != WEBKIT_POLICY_DECISION_TYPE_NAVIGATION_ACTION && type != WEBKIT_POLICY_DECISION_TYPE_NEW_WINDOW_ACTION) return FALSE;
  auto* action = webkit_navigation_policy_decision_get_navigation_action(WEBKIT_NAVIGATION_POLICY_DECISION(decision));
  const char* uri = webkit_uri_request_get_uri(webkit_navigation_action_get_request(action));
  if (g_str_has_prefix(uri, "busybooks://reader/") || g_str_has_prefix(uri, "blob:") || strcmp(uri,"about:blank")==0) return FALSE;
  webkit_policy_decision_ignore(decision); return TRUE;
}
static void call(FlMethodChannel*, FlMethodCall* method, gpointer data) {
  auto* h = static_cast<BusyBooksReaderHost*>(data);
  const char* name = fl_method_call_get_name(method);
  auto* args = fl_method_call_get_args(method);
  if (strcmp(name, "surface") == 0) {
    auto* value=fl_value_lookup_string(args,"canvas");
    if(value&&fl_value_get_type(value)==FL_VALUE_TYPE_INT){
      auto color=static_cast<guint32>(fl_value_get_int(value));
      GdkRGBA rgba{((color>>16)&255)/255.0,((color>>8)&255)/255.0,(color&255)/255.0,1};
      webkit_web_view_set_background_color(h->web,&rgba);
    }
  } else if (strcmp(name, "popoverResult") == 0) {
    h->popover->Result(args);
  } else if (strcmp(name, "capturePopover") == 0) {
    h->popover->Capture(method);
    return;
  } else if (strcmp(name, "popover") == 0) {
    h->popover->Show(method);
    return;
  } else if (strcmp(name, "dismissPopover") == 0) {
    h->popover->Hide();
    auto* restore = args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP
        ? fl_value_lookup_string(args, "restoreFocus") : nullptr;
    if (!restore || fl_value_get_type(restore) != FL_VALUE_TYPE_BOOL || fl_value_get_bool(restore))
      gtk_widget_grab_focus(GTK_WIDGET(h->web));
  } else if (strcmp(name, "focus") == 0) {
    auto* widget=GTK_WIDGET(h->web);
    auto* window=gtk_widget_get_toplevel(widget);
    if(gtk_widget_get_mapped(widget)&&GTK_IS_WINDOW(window)&&gtk_window_is_active(GTK_WINDOW(window)))gtk_widget_grab_focus(widget);
  } else if (strcmp(name, "open") == 0) {
    h->popover->Hide();
    auto* path_value = args && fl_value_get_type(args)==FL_VALUE_TYPE_MAP ? fl_value_lookup_string(args,"publicationPath") : nullptr;
    auto* cache_value = args && fl_value_get_type(args)==FL_VALUE_TYPE_MAP ? fl_value_lookup_string(args,"cacheDirectory") : nullptr;
    const char* path = path_value && fl_value_get_type(path_value)==FL_VALUE_TYPE_STRING ? fl_value_get_string(path_value) : nullptr;
    const char* cache = cache_value && fl_value_get_type(cache_value)==FL_VALUE_TYPE_STRING ? fl_value_get_string(cache_value) : nullptr;
    if (!path || !cache || !g_path_is_absolute(path) || !g_path_is_absolute(cache)) { fl_method_call_respond_error(method,"reader-path","Absolute publication and cache paths are required",nullptr,nullptr);return; }
    h->publication=path; h->cache_directory=cache;
    auto* session_value=fl_value_lookup_string(args,"session");
    const char* session=session_value&&fl_value_get_type(session_value)==FL_VALUE_TYPE_STRING?fl_value_get_string(session_value):"";
    if(!*session||strspn(session,"0123456789")!=strlen(session)){fl_method_call_respond_error(method,"reader-session","Invalid reader session",nullptr,nullptr);return;}
    h->session=session;
    auto* loading_value=fl_value_lookup_string(args,"loadingQuery");
    const char* loading=loading_value&&fl_value_get_type(loading_value)==FL_VALUE_TYPE_STRING?fl_value_get_string(loading_value):"";
    std::string uri="busybooks://reader/index_linux.html?session="+h->session+"&loading="+loading;
    webkit_web_view_load_uri(h->web,uri.c_str());
  } else if (strcmp(name,"bounds") == 0) {
    auto number=[args](const char* key){auto* v=fl_value_lookup_string(args,key);return v?static_cast<int>(fl_value_get_float(v)):0;};
    h->popover->Hide();
    h->surface->SetBounds(number("x"),number("y"),number("width"),number("height"));
  } else if (strcmp(name,"visible") == 0) {
    const bool visible = fl_value_get_bool(args);
    if (!visible) h->popover->Hide();
    h->surface->SetVisible(visible);
    // WebKit may retain GTK keyboard ownership after it is hidden for Notebook
    // or a Flutter dialog. Return it to the owning main view, without activating
    // an inactive application or focusing a transient editor.
    if (!visible && gtk_widget_get_mapped(h->chrome)) {
      auto* window = gtk_widget_get_toplevel(h->chrome);
      if (GTK_IS_WINDOW(window) && gtk_window_is_active(GTK_WINDOW(window)))
        gtk_widget_grab_focus(h->chrome);
    }
  } else if (strcmp(name,"dispatch") == 0) {
    const char* json=fl_value_get_string(args);
    if (!json || strlen(json)>1048576) {
      const std::string error="{\"type\":\"bridgeError\",\"session\":\""+h->session+"\",\"direction\":\"command\",\"message\":\"Reader bridge frame limit exceeded\"}";
      emit(h,error.c_str());
      fl_method_call_respond_error(method,"reader-bridge-limit","Reader bridge frame limit exceeded",nullptr,nullptr);return;
    }
    std::string script="window.busybooks?.dispatch("+std::string(json)+")";
    webkit_web_view_evaluate_javascript(h->web,script.c_str(),-1,nullptr,nullptr,nullptr,nullptr,nullptr);
  } else if (strcmp(name,"close") == 0) {
    h->popover->Hide();
    h->surface->SetVisible(false);
    h->session.clear();
    webkit_web_view_load_uri(h->web,"about:blank"); h->publication.clear(); h->cache_directory.clear();
  } else {fl_method_call_respond_not_implemented(method,nullptr);return;}
  fl_method_call_respond_success(method,nullptr,nullptr);
}
BusyBooksReaderHost* busybooks_reader_host_new(GtkWidget* overlay, FlView* view) {
  auto* h=new BusyBooksReaderHost{};
  h->chrome=GTK_WIDGET(g_object_ref(view));
  g_autofree char* exe=g_file_read_link("/proc/self/exe",nullptr);
  g_autofree char* dir=g_path_get_dirname(exe);
  h->assets=std::string(dir)+"/data/flutter_assets/assets/reader";
  h->context=webkit_web_context_new_ephemeral();
  webkit_web_context_set_cache_model(h->context,WEBKIT_CACHE_MODEL_DOCUMENT_VIEWER);
  webkit_web_context_register_uri_scheme(h->context,"busybooks",scheme,h,nullptr);
  auto* security=webkit_web_context_get_security_manager(h->context);
  webkit_security_manager_register_uri_scheme_as_secure(security,"busybooks");
  webkit_security_manager_register_uri_scheme_as_cors_enabled(security,"busybooks");
  auto* manager=webkit_user_content_manager_new();
  webkit_user_content_manager_register_script_message_handler(manager,"busybooks");
  g_signal_connect(manager,"script-message-received::busybooks",G_CALLBACK(message),h);
  h->web=WEBKIT_WEB_VIEW(g_object_new(WEBKIT_TYPE_WEB_VIEW,"web-context",h->context,"user-content-manager",manager,nullptr));
  g_object_unref(manager);
  WebKitSettings* settings=webkit_web_view_get_settings(h->web);
  webkit_settings_set_enable_developer_extras(settings,FALSE);
  webkit_settings_set_enable_html5_database(settings,FALSE);
  webkit_settings_set_enable_html5_local_storage(settings,FALSE);
  webkit_settings_set_enable_page_cache(settings,FALSE);
  webkit_settings_set_enable_caret_browsing(settings,TRUE);
  g_signal_connect(h->web,"decide-policy",G_CALLBACK(policy),h);
  g_signal_connect(h->web,"load-failed",G_CALLBACK(load_failed),h);
  g_signal_connect(h->web,"web-process-terminated",G_CALLBACK(process_terminated),h);
  h->fonts=busybooks_reading_font_channel_new(fl_engine_get_binary_messenger(fl_view_get_engine(view)));
  h->popover=new ReaderPopover(GTK_WIDGET(view), [h](const char* json) { emit(h, json, kMaxReaderPopoverActionBytes); });
  h->surface=new BusyBooksReaderSurface(GTK_OVERLAY(overlay),GTK_WIDGET(h->web));
  g_autoptr(FlStandardMethodCodec) codec=fl_standard_method_codec_new();
  h->channel=fl_method_channel_new(fl_engine_get_binary_messenger(fl_view_get_engine(view)),"io.busystack.busybooks/reader",FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(h->channel,call,h,nullptr);
  return h;
}
void busybooks_reader_host_free(BusyBooksReaderHost* h) {
  if(!h)return;
  fl_method_channel_set_method_call_handler(h->channel,nullptr,nullptr,nullptr);
  h->session.clear();
  g_signal_handlers_disconnect_by_data(h->web,h);
  g_signal_handlers_disconnect_by_data(webkit_web_view_get_user_content_manager(h->web),h);
  webkit_web_view_stop_loading(h->web);
  delete h->popover;
  delete h->surface;
  fl_method_channel_set_method_call_handler(h->fonts,nullptr,nullptr,nullptr);
  g_clear_object(&h->fonts);
  g_clear_object(&h->chrome);
  g_clear_object(&h->channel);g_clear_object(&h->context);delete h;
}

#include <gtk/gtk.h>
#include <webkit2/webkit2.h>
#include <string>
#include <cstdio>
#include <cstring>
#include <filesystem>
static const char* assets;
static std::string book,format,cache_directory;
static WebKitWebView* view;
static bool opened=false,location=false,search=false;
static void js(const char* text){webkit_web_view_evaluate_javascript(view,text,-1,nullptr,nullptr,nullptr,nullptr,nullptr);}
static void message(WebKitUserContentManager*,WebKitJavascriptResult* result,gpointer){auto* value=webkit_javascript_result_get_js_value(result);g_autofree char* text=jsc_value_to_string(value);printf("%s\n",text);fflush(stdout);
 if(strstr(text,"\"type\":\"ready\"")){std::string command="busybooks.dispatch({action:'open',format:'"+format+"',labels:{printPage:'Print page',page:'Page'},title:'BusyBooks fixture',appearance:{publisher:false,size:22,flow:'paginated'},annotations:[]})";js(command.c_str());}
 if(strstr(text,"\"type\":\"opened\"")){opened=true;js("busybooks.dispatch({action:'search',query:'library'})");}
 if(strstr(text,"\"type\":\"location\""))location=true;
 if(strstr(text,"\"type\":\"match\"")||strstr(text,"\"type\":\"matches\""))search=true;
 if(strstr(text,"\"type\":\"searchDone\"")){printf("PROBE_RESULT opened=%d location=%d search=%d\n",opened,location,search);gtk_main_quit();}
}
static void scheme(WebKitURISchemeRequest* r,gpointer){const char* rel=webkit_uri_scheme_request_get_path(r);std::string path; if(strcmp(rel,"/publication")==0)path=book; else if(strcmp(rel,"/book-index")==0||strncmp(rel,"/book/",6)==0){path=strcmp(rel,"/book-index")==0?cache_directory+".json":cache_directory+"/"+std::string(rel+6);}else path=std::string(assets)+rel;g_autoptr(GFile) file=g_file_new_for_path(path.c_str());g_autoptr(GError) error=nullptr;auto* stream=g_file_read(file,nullptr,&error);if(!stream){webkit_uri_scheme_request_finish_error(r,error);return;}const char* mime=g_str_has_suffix(rel,".html")?"text/html":g_str_has_suffix(rel,".css")?"text/css":g_str_has_suffix(rel,".js")||g_str_has_suffix(rel,".mjs")?"text/javascript":"application/octet-stream";webkit_uri_scheme_request_finish(r,G_INPUT_STREAM(stream),-1,mime);g_object_unref(stream);}
static gboolean timeout(gpointer){fprintf(stderr,"PROBE_TIMEOUT\n");gtk_main_quit();return G_SOURCE_REMOVE;}
int main(int argc,char**argv){if(argc<5)return 2;book=argv[1];format=argv[2];assets=argv[3];cache_directory=argv[4];gtk_init(&argc,&argv);auto* context=webkit_web_context_new_ephemeral();webkit_web_context_register_uri_scheme(context,"busybooks",scheme,nullptr,nullptr);auto* security=webkit_web_context_get_security_manager(context);webkit_security_manager_register_uri_scheme_as_secure(security,"busybooks");webkit_security_manager_register_uri_scheme_as_cors_enabled(security,"busybooks");auto* manager=webkit_user_content_manager_new();webkit_user_content_manager_register_script_message_handler(manager,"busybooks");g_signal_connect(manager,"script-message-received::busybooks",G_CALLBACK(message),nullptr);view=WEBKIT_WEB_VIEW(g_object_new(WEBKIT_TYPE_WEB_VIEW,"web-context",context,"user-content-manager",manager,nullptr));auto* window=gtk_window_new(GTK_WINDOW_TOPLEVEL);gtk_window_set_title(GTK_WINDOW(window),"BusyBooks Engine Probe");gtk_window_set_default_size(GTK_WINDOW(window),1000,700);gtk_container_add(GTK_CONTAINER(window),GTK_WIDGET(view));gtk_widget_show_all(window);webkit_web_view_load_uri(view,"busybooks://reader/index_linux.html");g_timeout_add_seconds(35,timeout,nullptr);gtk_main();gtk_widget_destroy(window);g_object_unref(manager);g_object_unref(context);return opened&&location&&search?0:1;}

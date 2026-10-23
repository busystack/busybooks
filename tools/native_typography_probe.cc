// Executes native discovery/preview and the actual Foliate adapter in WebKitGTK.
#include "../native/reading_fonts.h"
#include <gtk/gtk.h>
#include <webkit2/webkit2.h>
#include <algorithm>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <string>
#include <stdexcept>

namespace {
std::string assets, publication, cache, proof, probe_mode, proof_output;
WebKitWebView* web;
bool passed = false;
bool proof_started = false;
std::string quote(const std::string& value) {
  std::string out = "\"";
  for (unsigned char c : value) {
    if (c == '"' || c == '\\') { out += '\\'; out += c; }
    else if (c < 32) { char escaped[7]; snprintf(escaped, sizeof escaped, "\\u%04x", c); out += escaped; }
    else out += c;
  }
  return out + '"';
}
std::string resolution(const reading_fonts::Resolution& font) {
  std::string json = "{\"family\":" + quote(font.family) + ",\"faces\":[";
  for (size_t i = 0; i < font.faces.size(); ++i) {
    if (i) json += ',';
    const auto& f = font.faces[i]; json += "{\"weight\":" + std::to_string(f.weight) + ",\"italic\":" + (f.italic ? "true" : "false") + ",\"sources\":[";
    for (size_t j = 0; j < f.sources.size(); ++j) { if (j) json += ','; json += quote(f.sources[j]); }
    json += "]}";
  }
  return json + "]}";
}
void js(const std::string& script) { webkit_web_view_evaluate_javascript(web, script.c_str(), -1, nullptr, nullptr, nullptr, nullptr, nullptr); }
std::string font_data;
void message(WebKitUserContentManager*, WebKitJavascriptResult* result, gpointer) {
  auto* value = webkit_javascript_result_get_js_value(result); g_autofree char* raw = jsc_value_to_string(value);
  const std::string text = raw ? raw : ""; printf("%s\n", text.c_str()); fflush(stdout);
  if (text.find("\"type\":\"ready\"") != std::string::npos) {
    const auto appearance = probe_mode == "specialist-cold" ? "{publisher:false,size:20,weight:400,flow:'paginated',font:(" + font_data + ")[1].choice,resolvedFont:(" + font_data + ")[1].resolved}" : "{publisher:true,size:20,flow:'paginated'}";
    js("busybooks.dispatch({action:'open',format:'" + std::string(probe_mode == "pdf" ? "pdf" : "epub") + "',title:'Typography probe',labels:{printPage:'Print page',page:'Page',footnote:'Footnote'},appearance:" + appearance + ",annotations:[]})");
  }
  if (!proof_started && text.find("\"type\":\"opened\"") != std::string::npos) {
    proof_started = true;
    std::ifstream file(proof); const std::string script((std::istreambuf_iterator<char>(file)), {});
    std::ifstream committed(proof_output + "/committed-appearance.json");
    const std::string saved((std::istreambuf_iterator<char>(committed)), {});
    js("window.nativeCommittedAppearance=" + (saved.empty() ? "null" : saved) + ";window.nativeFontData=" + font_data + ";window.typographyProbeMode=" + quote(probe_mode) + ";\n" + script);
  }
  if (text.find("\"type\":\"typographyProof\"") != std::string::npos) { passed = text.find("\"passed\":true") != std::string::npos; gtk_main_quit(); }
  if (text.find("\"type\":\"error\"") != std::string::npos) gtk_main_quit();
}
void scheme(WebKitURISchemeRequest* request, gpointer) {
  const char* rel = webkit_uri_scheme_request_get_path(request); std::string path;
  if (!strcmp(rel, "/publication")) path = publication;
  else if (!strcmp(rel, "/book-index")) path = cache + ".json";
  else if (!strncmp(rel, "/book/", 6)) path = cache + "/" + std::string(rel + 6);
  else path = assets + rel;
  g_autoptr(GFile) file = g_file_new_for_path(path.c_str()); g_autoptr(GError) error = nullptr;
  auto* stream = g_file_read(file, nullptr, &error); if (!stream) { webkit_uri_scheme_request_finish_error(request, error); return; }
  const char* mime = g_str_has_suffix(rel,".html") ? "text/html" : g_str_has_suffix(rel,".css") ? "text/css" : g_str_has_suffix(rel,".js") || g_str_has_suffix(rel,".mjs") ? "text/javascript" : "application/octet-stream";
  webkit_uri_scheme_request_finish(request, G_INPUT_STREAM(stream), -1, mime); g_object_unref(stream);
}
}
int main(int argc, char** argv) {
  if (argc != 7) return 2;
  publication = argv[1]; cache = argv[2]; assets = argv[3]; proof = argv[4]; const std::string output = argv[5]; const std::string mode = argv[6]; probe_mode = mode;
  proof_output = output;
  try {
    if (!reading_fonts::ValidName("📖 Reading") || reading_fonts::ValidName(std::string(257, 'x')) || reading_fonts::ValidName(std::string("bad\nname"))) throw std::runtime_error("Invalid native font validation");
    std::string astral; for (int i = 0; i < 129; ++i) astral += "📖";
    if (reading_fonts::ValidName(astral)) throw std::runtime_error("Native font names must use the shared UTF-16 bound");
    const auto catalogue = reading_fonts::Discover(true);
    const std::string names[] = {"Noto Serif", "Liberation Sans", mode == "system" ? "DejaVu Sans" : "BusyBooks \"Ä\", \\ Serif", mode == "system" ? "Lato" : "BusyBooks Weight Proof"};
    font_data = "["; std::vector<std::vector<uint8_t>> images;
    size_t face_count = 0;
    for (size_t i = 0; i < 4; ++i) {
      if (std::none_of(catalogue.begin(), catalogue.end(), [&](const auto& f) { return f.id == names[i]; })) throw std::runtime_error("Deterministic font missing from native catalogue: " + names[i]);
      const auto font = reading_fonts::Resolve(names[i], false);
      face_count += font.faces.size();
      if (i) font_data += ',';
      font_data += "{\"choice\":{\"family\":" + quote(names[i]) + "},\"resolved\":" + resolution(font) + "}";
      reading_fonts::Sample sample; sample.prose = "A quiet morning — 0123456789."; sample.bold = "Bold emphasis."; sample.italic = "Italic voice.";
      auto image = reading_fonts::Preview(names[i], false, sample); images.push_back(image);
      std::ofstream png(output + "/native-sample-" + std::to_string(i) + ".png", std::ios::binary); png.write(reinterpret_cast<const char*>(image.data()), image.size());
    }
    font_data += "]";
    if (images[0] == images[1]) throw std::runtime_error("Distinct native families produced identical previews");
    std::vector<std::vector<uint8_t>> weighted_samples;
    for (int weight : {300, 400, 500, 600, 700}) {
      reading_fonts::Sample sample; sample.prose = "A quiet library, 0123456789."; sample.bold = "Bold emphasis."; sample.italic = "An italic voice."; sample.weight = weight;
      const auto pixels = reading_fonts::Preview(names[3], false, sample);
      if (std::find(weighted_samples.begin(), weighted_samples.end(), pixels) != weighted_samples.end()) throw std::runtime_error("Native preview collapsed distinct body weights");
      weighted_samples.push_back(pixels);
    }
    printf("NATIVE_CATALOGUE families=%zu local_faces=%zu distinct_previews=1\n", catalogue.size(), face_count);
    std::ofstream metadata(output + "/native-fonts.json"); metadata << font_data;
    if (mode == "catalogue") return 0;
  } catch (const std::exception& error) { fprintf(stderr, "%s\n", error.what()); return 1; }
  gtk_init(&argc, &argv);
  auto* context = webkit_web_context_new_ephemeral(); webkit_web_context_register_uri_scheme(context, "busybooks", scheme, nullptr, nullptr);
  auto* security = webkit_web_context_get_security_manager(context); webkit_security_manager_register_uri_scheme_as_secure(security, "busybooks"); webkit_security_manager_register_uri_scheme_as_cors_enabled(security, "busybooks");
  auto* manager = webkit_user_content_manager_new(); webkit_user_content_manager_register_script_message_handler(manager, "busybooks"); g_signal_connect(manager,"script-message-received::busybooks",G_CALLBACK(message),nullptr);
  web = WEBKIT_WEB_VIEW(g_object_new(WEBKIT_TYPE_WEB_VIEW, "web-context", context, "user-content-manager", manager, nullptr));
  auto* window = gtk_window_new(GTK_WINDOW_TOPLEVEL); gtk_window_set_title(GTK_WINDOW(window), "BusyBooks Native Typography Verification"); gtk_window_set_default_size(GTK_WINDOW(window), 1000, 700); gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(web)); gtk_widget_show_all(window);
  webkit_web_view_load_uri(web, "busybooks://reader/index_linux.html");
  const auto timeout = g_timeout_add_seconds(45, +[](gpointer) -> gboolean { fprintf(stderr,"TYPOGRAPHY_PROBE_TIMEOUT\n"); gtk_main_quit(); return G_SOURCE_REMOVE; }, nullptr);
  gtk_main(); if (passed) g_source_remove(timeout); gtk_widget_destroy(window); g_object_unref(manager); g_object_unref(context); return passed ? 0 : 1;
}

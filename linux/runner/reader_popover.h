#ifndef BUSYBOOKS_READER_POPOVER_H_
#define BUSYBOOKS_READER_POPOVER_H_
#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <functional>
#include <string>
#include <memory>
// An owned Flutter view is above, rather than replacing, the book's native view.
// It uses the same AOT bundle and shared app controls, without initializing stores.
class ReaderPopover {
 public:
  ReaderPopover(GtkWidget* anchor, std::function<void(const char*)> event);
  ~ReaderPopover();
  void Show(FlMethodCall* call);
  void Hide();
  void Result(FlValue* data);
  void Capture(FlMethodCall* call);
 private:
  void EnsureView();
  void Update();
  void Complete(const char* code = nullptr);
  void Present();
  bool Matches(FlValue* value) const;
  static gboolean Timeout(gpointer);
  static void Call(FlMethodChannel*, FlMethodCall*, gpointer);
  static void Frame(FlView*, gpointer);
  GtkWidget* anchor_;
  GtkWidget* popover_ = nullptr;
  FlView* view_ = nullptr;
  FlMethodChannel* channel_ = nullptr;
  FlValue* data_ = nullptr;
  bool ready_ = false, frame_ = false, requested_ = false, painted_ = false, restart_ = false;
  bool keyboard_dismissal_ = false;
  FlMethodCall* pending_ = nullptr;
  guint timeout_ = 0;
  int maximum_height_ = 480;
  std::shared_ptr<bool> alive_ = std::make_shared<bool>(true);
  std::function<void(const char*)> event_;
};
#endif

// Adapted from BusyMark (BusyStack, Apache-2.0); modified for BusyBooks.
#ifndef RUNNER_GTK_WINDOW_PREFERENCES_H_
#define RUNNER_GTK_WINDOW_PREFERENCES_H_

#include <gtk/gtk.h>

#include <array>
#include <functional>
#include <string>

struct BusyBooksGtkWindowPreferences {
  std::string decoration_layout;
  std::string double_click;
  std::string middle_click;
  std::string right_click;
};

class BusyBooksGtkWindowPreferencesWatcher {
 public:
  using ChangedCallback =
      std::function<void(const BusyBooksGtkWindowPreferences&)>;

  explicit BusyBooksGtkWindowPreferencesWatcher(GtkSettings* settings = nullptr);
  ~BusyBooksGtkWindowPreferencesWatcher();

  BusyBooksGtkWindowPreferencesWatcher(
      const BusyBooksGtkWindowPreferencesWatcher&) = delete;
  BusyBooksGtkWindowPreferencesWatcher& operator=(
      const BusyBooksGtkWindowPreferencesWatcher&) = delete;

  BusyBooksGtkWindowPreferences Read() const;
  static BusyBooksGtkWindowPreferences Defaults();
  bool Start(ChangedCallback callback);
  void Stop();

  std::array<gulong, 4> signal_ids() const;

 private:
  static void OnSettingChanged(GObject* object,
                               GParamSpec* specification,
                               gpointer user_data);
  GtkSettings* ResolveSettings() const;

  GtkSettings* settings_;
  ChangedCallback callback_;
  std::array<gulong, 4> signal_ids_ = {0, 0, 0, 0};
};

#endif  // RUNNER_GTK_WINDOW_PREFERENCES_H_

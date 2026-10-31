#ifndef BUSYBOOKS_MENU_SELECTION_H_
#define BUSYBOOKS_MENU_SELECTION_H_

// A contiguous run of radio entries is one exclusive group. Availability is
// independent of selection: a selected command may become disabled while work
// is loading. Both desktop hosts enforce this same contract before presenting.
class MenuSelectionGroup {
 public:
  bool Add(bool separator, bool checkable, bool exclusive, bool selected) {
    if (selected && !checkable) return false;
    if (separator || !checkable || !exclusive) {
      selected_count_ = 0;
      return true;
    }
    if (selected) ++selected_count_;
    return selected_count_ <= 1;
  }

 private:
  unsigned selected_count_ = 0;
};

#endif  // BUSYBOOKS_MENU_SELECTION_H_

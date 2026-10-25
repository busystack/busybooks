#include <cassert>
#include "../../native/menu_selection.h"

int main() {
  MenuSelectionGroup group;
  // Enabled/disabled status deliberately does not participate in grouping.
  assert(group.Add(false, true, true, true));
  assert(group.Add(false, true, true, false));
  assert(!group.Add(false, true, true, true));
  assert(group.Add(true, false, false, false));
  assert(group.Add(false, true, true, true));
  assert(group.Add(false, true, false, true));  // Independent toggle.
  assert(group.Add(false, true, true, true));
  assert(!group.Add(false, false, false, true));
}

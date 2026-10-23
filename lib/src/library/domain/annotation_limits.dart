/// Existing reading-data contract, measured in Dart/JSON UTF-16 code units.
const maxAnnotationTextLength = 1000000;

bool validAnnotationText(String text) =>
    text.length <= maxAnnotationTextLength && !text.contains('\u0000');

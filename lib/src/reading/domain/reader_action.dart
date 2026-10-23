import 'dart:convert';
import '../../library/domain/annotation_limits.dart';

// A JSON string needs at most six UTF-8 bytes per UTF-16 unit (\uXXXX).
// Reserve a bounded 64 KiB for the action envelope. This larger allowance is
// exclusive to popover actions; ordinary publication events keep their limit.
// Keep native/reader_action_limits.h in agreement (verified by tests).
const maxReaderPopoverActionBytes = 6 * maxAnnotationTextLength + 65536;

bool validReaderPopoverAction(String encoded) =>
    encoded.length <= maxReaderPopoverActionBytes &&
    utf8.encode(encoded).length <= maxReaderPopoverActionBytes;

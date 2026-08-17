import '../models/robo_command.dart';

/// Parses raw text strings into [RoboCommand] objects.
class RoboParser {
  /// Parses a single line of command text.
  /// Supported formats:
  /// - `A=point(3,3)`
  /// - `a=line(A,B)`
  /// - `text('Hello')`
  static RoboCommand? parse(String line) {
    line = line.trim();
    if (line.isEmpty) return null;

    // Check for variable assignment: `var = command(...)`
    String? assignedVar;
    String cmdString = line;

    final assignMatch = RegExp(r'^([a-zA-Z0-9_]+)\s*=\s*(.*)$').firstMatch(line);
    if (assignMatch != null) {
      assignedVar = assignMatch.group(1)!;
      cmdString = assignMatch.group(2)!;
    }

    // Extract command name and arguments: `command(arg1, arg2)`
    final match = RegExp(r'^([a-zA-Z0-9_]+)\((.*)\)$').firstMatch(cmdString);
    if (match != null) {
      final cmdName = match.group(1)!.toLowerCase();
      final argsString = match.group(2)!;
      
      final args = _splitArgs(argsString);

      switch (cmdName) {
        case 'point':
          if (args.length == 2) {
            double? x = double.tryParse(args[0]);
            double? y = double.tryParse(args[1]);
            // Allow arguments to be numeric or string references
            return RoboPointCommand(line, assignedVar, x ?? args[0], y ?? args[1]);
          } else if (args.length == 1) {
            return RoboPointCommand(line, assignedVar, args[0], null);
          }
          break;
        case 'line':
          if (args.length == 2) {
            return RoboLineCommand(line, assignedVar, args[0], args[1]);
          } else if (args.length == 3) {
            double? x = double.tryParse(args[1]);
            double? y = double.tryParse(args[2]);
            return RoboLineCommand(line, assignedVar, args[0], {'type': 'point', 'x': x ?? args[1], 'y': y ?? args[2]});
          }
          break;
        case 'circle':
          if (args.length == 2) {
            double? r = double.tryParse(args[1]);
            return RoboCircleCommand(line, assignedVar, args[0], r ?? args[1]);
          }
          break;
        case 'arc':
          if (args.length == 4) {
            double? r = double.tryParse(args[1]);
            double? start = double.tryParse(args[2]);
            double? sweep = double.tryParse(args[3]);
            return RoboArcCommand(line, assignedVar, args[0], r ?? args[1], start ?? args[2], sweep ?? args[3]);
          } else if (args.length == 5) {
            double? start = double.tryParse(args[3]);
            double? sweep = double.tryParse(args[4]);
            return RoboArcCommand.fromPoints(line, assignedVar, args[0], args[1], args[2], start ?? args[3], sweep ?? args[4]);
          }
          break;
        case 'stroke':
          if (args.length >= 2) {
            double? thickness = double.tryParse(args.last);
            if (thickness != null) {
              return RoboStrokeCommand(line, args.sublist(0, args.length - 1), thickness);
            }
          }
          break;
        case 'fade':
          if (args.length >= 2) {
            double? factor = double.tryParse(args.last);
            if (factor != null) {
              return RoboFadeCommand(line, args.sublist(0, args.length - 1), factor);
            }
          }
          break;
        case 'hide':
          if (args.isNotEmpty) {
            return RoboVisibilityCommand(line, args, true);
          }
          break;
        case 'show':
          if (args.isNotEmpty) {
            return RoboVisibilityCommand(line, args, false);
          }
          break;
        case 'pointtype':
          if (args.length == 1) {
            String type = args[0].replaceAll("'", "").replaceAll('"', '');
            return RoboPointTypeCommand(line, type);
          }
          break;
        case 'polygon':
          if (args.length >= 3) {
            return RoboPolygonCommand(line, assignedVar, args);
          }
          break;
        case 'dash':
          if (args.length == 6) {
            double? dl = double.tryParse(args[4]);
            double? gl = double.tryParse(args[5]);
            return RoboDashCommand(line, assignedVar, args[0], args[1], dl ?? 0.5, gl ?? 0.5);
          }
          break;
        case 'group':
          if (args.isNotEmpty) {
            return RoboGroupCommand(line, assignedVar, args);
          }
          break;
        case 'rotate':
          if (args.length >= 2) {
            double? angle = double.tryParse(args[1]);
            return RoboTransformCommand(line, assignedVar, args[0], 'rotate', [angle ?? args[1], if (args.length > 2) args[2]]);
          }
          break;
        case 'translate':
          if (args.length >= 3) {
            double? tx = double.tryParse(args[1]);
            double? ty = double.tryParse(args[2]);
            return RoboTransformCommand(line, assignedVar, args[0], 'translate', [tx ?? args[1], ty ?? args[2], if (args.length > 3) args[3]]);
          }
          break;
        case 'dilate':
          if (args.length >= 2) {
            double? scale = double.tryParse(args[1]);
            return RoboTransformCommand(line, assignedVar, args[0], 'dilate', [scale ?? args[1], if (args.length > 2) args[2]]);
          }
          break;
        case 'reflect':
          if (args.length >= 2) {
            return RoboTransformCommand(line, assignedVar, args[0], 'reflect', [args[1]]);
          }
          break;
        case 'reverse':
          if (args.isNotEmpty) {
            return RoboTransformCommand(line, assignedVar, args[0], 'reverse', []);
          }
          break;
        case 'x':
        case 'y':
        case 'dist':
        case 'pos':
        case 'interpolate':
        case 'project':
        case 'findangle':
        case 'perp':
        case 'parallel':
        case 'angle':
        case 'intersect':
        case 'tick':
          if (args.isNotEmpty) {
            return RoboMathCommand(line, assignedVar, cmdName, args);
          }
          break;
        case 'plot':
          if (args.isNotEmpty) {
            return RoboPlotCommand(line, assignedVar, args[0], args.length > 1 ? args[1] : null, args.length > 2 ? args[2] : null);
          }
          break;
        case 'text':
          if (args.isNotEmpty) {
            return RoboTextCommand(line, args[0], args.length > 1 ? args[1] : null, args.length > 2 ? args[2] : null);
          }
          break;
        case 'fill':
          if (args.isNotEmpty) {
            return RoboFillCommand(line, assignedVar, args);
          }
          break;
        case 'and':
        case 'or':
        case 'diff':
          if (args.length >= 2) {
            return RoboBooleanCommand(line, assignedVar, cmdName, args);
          }
          break;
        case 'para':
          if (args.length >= 2) {
            return RoboParaCommand(line, assignedVar, args[0], args[1], args.length > 2 ? args[2] : null, args.length > 3 ? args[3] : null, args.length > 4 ? args[4] : null);
          }
          break;
        case 'trace':
          if (args.isNotEmpty) {
            return RoboTraceCommand(line, assignedVar, args);
          }
          break;
        case 'part':
          if (args.length >= 3) {
            return RoboPartCommand(line, assignedVar, args[0], args[1], args[2], args.length > 3 ? args[3] : null);
          }
          break;
        case 'text':
          if (args.isNotEmpty) {
            String text = args.join(',').replaceAll("'", "").replaceAll('"', '');
            return RoboTextCommand(line, text);
          }
          break;
      }
    }

    return null; // Unsupported or invalid command
  }

  static List<String> _splitArgs(String argsString) {
    List<String> args = [];
    int bracketCount = 0;
    StringBuffer currentArg = StringBuffer();

    for (int i = 0; i < argsString.length; i++) {
      String char = argsString[i];
      if (char == '(') bracketCount++;
      if (char == ')') bracketCount--;

      if (char == ',' && bracketCount == 0) {
        args.add(currentArg.toString().trim());
        currentArg.clear();
      } else {
        currentArg.write(char);
      }
    }
    if (currentArg.isNotEmpty) {
      args.add(currentArg.toString().trim());
    }
    return args;
  }
}

import 'robo_drawing_data.dart';

class RoboPresets {
  /// Loads the default professional presets for the Robo Drawing library.
  /// Separating this from the UI keeps our code clean and maintainable.
  static List<RoboDrawingData> loadPresets() {
    return [
      RoboDrawingData(
        name: "Bisection of an Angle",
        commands: [
          "text('Construct a line which bisects an angle')",
          "A=point(3,3)",
          "B=point(14,3)",
          "a=line(A,B)",
          "b=line(A,9.5,14)",
          "text('Draw an arc with center A of any radius')",
          "c=arc(A,5,330,120)",
          "C=point(intersect(a,c))",
          "D=point(intersect(b,c))",
          "text('Draw an arc with center C of any radius greather that half of CD')",
          "d=arc(C,4,20,60)",
          "text('Repeat this with center D using the same radius')",
          "e=arc(D,4,330,60)",
          "E=point(intersect(d,e))",
          "text('Join A to the point where arcs cross.')",
          "c=line(A,E)",
          "findangle(b,c)",
          "findangle(a,c)",
        ],
      ),
      RoboDrawingData(
        name: "Equilateral Triangle",
        commands: [
          "text('Construct an Equilateral Triangle')",
          "A=point(6,12)",
          "B=point(14,12)",
          "base=line(A,B)",
          "text('Draw an arc from A with radius AB')",
          "arcA=arc(A,8,270,90)",
          "text('Draw an arc from B with radius AB')",
          "arcB=arc(B,8,180,90)",
          "text('Mark the intersection point C')",
          "C=point(intersect(arcA,arcB))",
          "text('Connect the points to form the triangle')",
          "side1=line(A,C)",
          "side2=line(B,C)",
        ],
      ),
      RoboDrawingData(
        name: "Perpendicular Bisector",
        commands: [
          "text('Construct a perpendicular bisector')",
          "A=point(5,10)",
          "B=point(15,10)",
          "base=line(A,B)",
          "text('Draw an arc from A with radius > half AB')",
          "arcA=arc(A,7,270,90)",
          "text('Draw an arc from B with same radius')",
          "arcB=arc(B,7,90,270)",
          "text('Mark the intersection point')",
          "C=point(intersect(arcA,arcB))",
          "text('Draw the bisector line downwards')",
          "bisector=line(C,10,16)",
        ],
      ),
    ];
  }
}

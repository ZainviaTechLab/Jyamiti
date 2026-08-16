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
          "text('Constructing an Equilateral Triangle')",
          "A=point(4,5)",
          "B=point(12,5)",
          "text('Draw segment a = AB between points A and B')",
          "a=line(A,B)",
          "text('Construct an arc c with center B and radius which is length of segment a.')",
          "c=arc(a,B,90,90)",
          "text('Intersect an arc c with an arc d with center A.')",
          "d=arc(a,A,0,90)",
          "C=point(intersect(c,d))",
          "text('Draw an equilateral triangle.')",
          "e=line(B,C)",
          "f=line(C,A)",
          "hide(c,d)",
        ],
      ),
      RoboDrawingData(
        name: "Copy a Line Segment",
        commands: [
          "text('Constructing a copy of a line segment')",
          "A=point(4,5)",
          "B=point(10,5)",
          "text('Draw the original segment a = AB')",
          "a=line(A,B)",
          "text('Pick a new starting point C')",
          "C=point(4,10)",
          "text('Draw a long line l starting from C')",
          "l=line(C,15,10)",
          "text('Measure segment AB and draw an arc from C')",
          "c=arc(a,C,-30,60)",
          "text('Mark the intersection point E')",
          "E=point(intersect(l,c))",
          "text('Segment CE is an exact copy of AB')",
          "hide(l,c)",
          "line(C,E)",
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

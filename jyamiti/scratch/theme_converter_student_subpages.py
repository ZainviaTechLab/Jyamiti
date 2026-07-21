import os
import re

files = [
    r"c:\Users\USER\Desktop\myprojects\Jyamiti final\jyamiti\lib\presentation\features\dashboard\screens\student_performance_screen.dart",
    r"c:\Users\USER\Desktop\myprojects\Jyamiti final\jyamiti\lib\presentation\features\dashboard\screens\student_detailed_attendance_screen.dart",
    r"c:\Users\USER\Desktop\myprojects\Jyamiti final\jyamiti\lib\presentation\features\dashboard\screens\student_payments_screen.dart",
    r"c:\Users\USER\Desktop\myprojects\Jyamiti final\jyamiti\lib\presentation\features\dashboard\screens\student_settings_screen.dart"
]

for filepath in files:
    if not os.path.exists(filepath):
        print(f"Skipping {filepath}")
        continue
        
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
        
    new_content = content
    
    # 1. AppBar iconTheme
    new_content = re.sub(r'iconTheme:\s*const\s*IconThemeData\(\s*color:\s*Colors\.white\s*\)', 'iconTheme: IconThemeData(color: context.textColor)', new_content)
    new_content = re.sub(r'iconTheme:\s*IconThemeData\(\s*color:\s*Colors\.white\s*\)', 'iconTheme: IconThemeData(color: context.textColor)', new_content)
    
    # 2. Dialog Backgrounds
    new_content = re.sub(r'backgroundColor:\s*const\s*Color\(0xFF1E293B\)', 'backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white', new_content)
    new_content = re.sub(r'backgroundColor:\s*Color\(0xFF1E293B\)', 'backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white', new_content)
    
    # 3. Colors.white10 in borders/lines inside charts/progress
    new_content = new_content.replace('backgroundColor: Colors.white10,', 'backgroundColor: context.isDark ? Colors.white10 : Colors.black12,')
    new_content = new_content.replace('FlLine(color: Colors.white10', 'FlLine(color: context.isDark ? Colors.white10 : Colors.black12')
    
    # 4. Text/Icon colors inside solid colored buttons should remain white
    new_content = new_content.replace("child: Text('Logout', style: TextStyle(color: context.textColor))", "child: const Text('Logout', style: TextStyle(color: Colors.white))")
    new_content = new_content.replace("child: Text('Reset', style: TextStyle(color: context.textColor))", "child: const Text('Reset', style: TextStyle(color: Colors.white))")
    new_content = new_content.replace("child: Text('Delete', style: TextStyle(color: context.textColor))", "child: const Text('Delete', style: TextStyle(color: Colors.white))")
    new_content = new_content.replace("child: Text('Retry', style: TextStyle(color: context.textColor))", "child: const Text('Retry', style: TextStyle(color: Colors.white))")
    new_content = new_content.replace("label: Text('Pay Now', style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold))", "label: const Text('Pay Now', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))")
    new_content = new_content.replace("icon: Icon(Icons.payment_rounded, color: context.textColor, size: 20)", "icon: const Icon(Icons.payment_rounded, color: Colors.white, size: 20)")
    
    # 5. Overdue payment card white due text
    new_content = new_content.replace('color: isOverdue ? Colors.redAccent : Colors.white,', 'color: isOverdue ? Colors.redAccent : context.textColor,')
    
    # Detailed Attendance Screen card upgrades
    if "student_detailed_attendance_screen.dart" in filepath:
        new_content = new_content.replace("""      decoration: BoxDecoration(
        color: context.glassBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.glassBorder),
        boxShadow: [BoxShadow(color: const Color(0xFF6366F1).withOpacity(0.1), blurRadius: 20, spreadRadius: -5)],
      ),""", """      decoration: BoxDecoration(
        color: context.isDark ? context.glassBg : Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.isDark ? context.glassBorder : Colors.white.withOpacity(0.6), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: context.isDark ? Colors.black.withOpacity(0.2) : const Color(0xFF6366F1).withOpacity(0.06),
            blurRadius: 30,
            offset: const Offset(0, 10),
          )
        ],
      ),""")
        
        # Recent attendance items list
        new_content = new_content.replace("""          decoration: BoxDecoration(
            color: context.glassBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.glassBg),
          ),""", """          decoration: BoxDecoration(
            color: context.isDark ? context.glassBg : Colors.white.withOpacity(0.65),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.isDark ? context.glassBorder : Colors.white.withOpacity(0.75)),
          ),""")

    # Performance Screen cards
    if "student_performance_screen.dart" in filepath:
        new_content = new_content.replace("""            decoration: BoxDecoration(
              color: context.glassBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: context.glassBorder),
              boxShadow: [BoxShadow(color: const Color(0xFF6366F1).withOpacity(0.1), blurRadius: 20, spreadRadius: -5)],
            ),""", """            decoration: BoxDecoration(
              color: context.isDark ? context.glassBg : Colors.white.withOpacity(0.85),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: context.isDark ? context.glassBorder : Colors.white.withOpacity(0.6), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: context.isDark ? Colors.black.withOpacity(0.2) : const Color(0xFF6366F1).withOpacity(0.06),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                )
              ],
            ),""")
            
        new_content = new_content.replace("""      decoration: BoxDecoration(
        color: context.glassBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.glassBorder),
        boxShadow: [BoxShadow(color: const Color(0xFF6366F1).withOpacity(0.1), blurRadius: 20, spreadRadius: -5)],
      ),""", """      decoration: BoxDecoration(
        color: context.isDark ? context.glassBg : Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.isDark ? context.glassBorder : Colors.white.withOpacity(0.6), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: context.isDark ? Colors.black.withOpacity(0.2) : const Color(0xFF6366F1).withOpacity(0.06),
            blurRadius: 30,
            offset: const Offset(0, 10),
          )
        ],
      ),""")
      
        new_content = new_content.replace("""      decoration: BoxDecoration(
        color: context.glassBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.glassBorder),
        boxShadow: [BoxShadow(color: const Color(0xFF6366F1).withOpacity(0.05), blurRadius: 10)],
      ),""", """      decoration: BoxDecoration(
        color: context.isDark ? context.glassBg : Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.isDark ? context.glassBorder : Colors.white.withOpacity(0.6), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: context.isDark ? Colors.black.withOpacity(0.2) : const Color(0xFF6366F1).withOpacity(0.06),
            blurRadius: 30,
            offset: const Offset(0, 10),
          )
        ],
      ),""")

    # Settings Screen cards
    if "student_settings_screen.dart" in filepath:
        new_content = new_content.replace("""      decoration: BoxDecoration(
        color: context.glassBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.glassBg),
      ),""", """      decoration: BoxDecoration(
        color: context.isDark ? context.glassBg : Colors.white.withOpacity(0.75),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.isDark ? context.glassBorder : Colors.white.withOpacity(0.55)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(context.isDark ? 0.15 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),""")
      
        new_content = new_content.replace("""      decoration: BoxDecoration(
        color: context.glassBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.3)),
        boxShadow: [
          BoxShadow(color: const Color(0xFF6366F1).withOpacity(0.1), blurRadius: 20, spreadRadius: -5),
        ],
      ),""", """      decoration: BoxDecoration(
        color: context.isDark ? context.glassBg : Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.isDark ? const Color(0xFF6366F1).withOpacity(0.3) : Colors.white.withOpacity(0.6), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: context.isDark ? Colors.black.withOpacity(0.2) : const Color(0xFF6366F1).withOpacity(0.06),
            blurRadius: 30,
            offset: const Offset(0, 10),
          )
        ],
      ),""")

        new_content = new_content.replace("""      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
      ),""", """      decoration: BoxDecoration(
        color: context.isDark ? color.withOpacity(0.05) : color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.isDark ? color.withOpacity(0.2) : color.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(context.isDark ? 0.05 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),""")

    # Payments Screen cards
    if "student_payments_screen.dart" in filepath:
        new_content = new_content.replace("""      decoration: BoxDecoration(
        color: const Color(0xFF10B981).withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withOpacity(0.1),
            blurRadius: 20,
            spreadRadius: -5,
          ),
        ],
      ),""", """      decoration: BoxDecoration(
        color: context.isDark ? const Color(0xFF10B981).withOpacity(0.05) : Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.isDark ? const Color(0xFF10B981).withOpacity(0.3) : Colors.white.withOpacity(0.6), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: context.isDark ? Colors.black.withOpacity(0.2) : const Color(0xFF10B981).withOpacity(0.06),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),""")
      
        new_content = new_content.replace("""      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor.withOpacity(0.4)),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 20,
            spreadRadius: -5,
          ),
        ],
      ),""", """      decoration: BoxDecoration(
        color: context.isDark ? bgColor : Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.isDark ? borderColor.withOpacity(0.4) : Colors.white.withOpacity(0.6), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: context.isDark ? Colors.black.withOpacity(0.2) : shadowColor.withOpacity(0.06),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),""")
      
        new_content = new_content.replace("""      decoration: BoxDecoration(
        color: context.glassBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.glassBorder),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withOpacity(0.05),
            blurRadius: 10,
          ),
        ],
      ),""", """      decoration: BoxDecoration(
        color: context.isDark ? context.glassBg : Colors.white.withOpacity(0.75),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.isDark ? context.glassBorder : Colors.white.withOpacity(0.55)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(context.isDark ? 0.15 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),""")

    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(new_content)
    print(f"Processed: {os.path.basename(filepath)}")

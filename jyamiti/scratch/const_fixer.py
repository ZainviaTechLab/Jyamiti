import os

def find_expression_end(text, start_idx):
    # Find the first opening char among (, [, { after start_idx
    first_open_idx = -1
    open_char = ''
    close_char = ''
    for idx in range(start_idx, min(start_idx + 500, len(text))):  # Increase lookahead to 500 to find first open brace
        if text[idx] in ('(', '[', '{'):
            first_open_idx = idx
            open_char = text[idx]
            close_char = { '(': ')', '[': ']', '{': '}' }[open_char]
            break
    if first_open_idx == -1:
        return -1
        
    depth = 0
    for idx in range(first_open_idx, len(text)):
        char = text[idx]
        if char == open_char:
            depth += 1
        elif char == close_char:
            depth -= 1
            if depth == 0:
                return idx
    return -1

def fix_file_consts(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
        
    modified = True
    iterations = 0
    while modified and iterations < 15:
        modified = False
        iterations += 1
        
        # Find all occurrences of 'const '
        idx = 0
        while True:
            idx = content.find('const ', idx)
            if idx == -1:
                break
                
            end_idx = find_expression_end(content, idx + 6)
            if end_idx != -1:
                expr = content[idx:end_idx + 1]
                # Check for dynamic elements inside the const expression
                if any(trigger in expr for trigger in ('context', 'roleColor', 'widget.', 'withOpacity', 'withValues', 'opacity', 'present', 'absent', 'leave')):
                    # Remove the 'const ' keyword
                    content = content[:idx] + content[idx + 6:]
                    modified = True
                    # Since we modified the content length, we restart the scan
                    break
            idx += 6
            
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)

# Process all screens under presentation/features
features_dir = r"c:\Users\USER\Desktop\myprojects\Jyamiti final\jyamiti\lib\presentation\features"
count = 0
for root, dirs, files in os.walk(features_dir):
    for file in files:
        if file.endswith(".dart"):
            fix_file_consts(os.path.join(root, file))
            count += 1

print(f"Processed {count} Dart files.")

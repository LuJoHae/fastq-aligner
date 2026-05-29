def get_line_count(filepath):
    with open(filepath, "r") as f:
        line_count = sum(1 for _ in f)
    return line_count
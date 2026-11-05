import re
def edit(m):
    n = len(re.findall(r'float (_\d+) = as_type<float>\(ssbo_2\.data\[_\d+\]\);', m)); assert n == 1, n
    return re.sub(r'float (_\d+) = as_type<float>\(ssbo_2\.data\[_\d+\]\);', r'float \1 = 2.0;', m)

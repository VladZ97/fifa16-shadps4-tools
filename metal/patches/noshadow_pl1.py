def edit(m):
    a = "        _1471 = _1470;\n"
    assert m.count(a) == 1
    return m.replace(a, "        _1471 = 1065353216u; // EXPERIMENT: shadow term forced lit\n")

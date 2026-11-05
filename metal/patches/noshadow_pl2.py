def edit(m):
    a = "        _2040 = _2039;\n"
    assert m.count(a) == 1
    return m.replace(a, "        _2040 = 1065353216u; // EXPERIMENT: shadow term forced lit\n")

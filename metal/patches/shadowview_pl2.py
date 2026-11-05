def edit(m):
    a = "    out.frag_color0.w = ((as_type<uint>(0.0) & 2147483647u) > 2139095040u) ? 0.0 : fast::clamp(0.0, 0.0, 64512.0);\n"
    assert m.count(a) == 1
    return m.replace(a, "    out.frag_color0.xyz = float3(as_type<float>(_2040)) * 2.0; // EXPERIMENT: shadow term as colour\n" + a)

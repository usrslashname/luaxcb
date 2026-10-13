local function normalize_lom_node(node)
    if node == nil then
        return nil
    end

    local out = {
        tag = node.name,
        text = node.text,
        attr = node.attr or {},
        children = {}
    }

    for _, child in ipairs(node.children or {}) do
        if type(child) == "table" and child.name then
            table.insert(out.children, normalize_lom_node(child))
        end
    end

    return out
end

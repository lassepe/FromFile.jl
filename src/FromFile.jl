module FromFile

export @from, @reexport

macro from(path::String, ex::Expr)
    esc(from_m(__module__, __source__, path, ex))
end

function from_m(m::Module, s::LineNumberNode, path::String, root_ex::Expr)
    import_exs = if root_ex.head === :block
        filter(ex -> !(ex isa LineNumberNode), root_ex.args)
    else
        [root_ex]
    end

    all(ex -> ex.head === :using || ex.head === :import, import_exs) || error("expected using/import statement")

	root = Base.moduleroot(m)
	basepath = dirname(String(s.file))

    # file path should always be relative to the
    # module loads it, unless specified as absolute
    # path or the module is created interactively
    if !isabspath(path) && basepath != ""
        path = joinpath(basepath, path)
    else
        path = abspath(path)
    end


    if root === Main
        file_module_sym = Symbol(path)
    else
        file_module_sym = Symbol(relpath(path, pathof(root)))
    end

    if isdefined(root, file_module_sym)
        file_module = getfield(root, file_module_sym)
    else
        file_module = Base.eval(root, :(module $(file_module_sym); include($path); end))
    end

    return Expr(:block, map(import_exs) do ex
        loading = Expr(ex.head)

        for each in ex.args
            each isa Expr || continue

            if each.head === :(:) # using/import A: a, b, c
                each.args[1].args[1] === :(.) && error("cannot load relative module from file")
                push!(loading.args, Expr(:(:), Expr(:., fullname(file_module)..., each.args[1].args...), each.args[2:end]...) )
            elseif each.head === :(.) # using/import A, B.C
                each.args[1] === :(.) && error("cannot load relative module from file")
                push!(loading.args, Expr(:., fullname(file_module)..., each.args...))
            else
                error("invalid syntax $ex")
            end
        end
        return loading
    end...)
end

macro reexport(ex::Expr)
    reexport(__module__, ex)
end

function reexport(m::Module, from_ex::Expr)
    from_ex.head === :macrocall && from_ex.args[1] === Symbol("@from") || error("The reexport macro can only be applied to a imports via the @from macro.")
    import_block_ex = macroexpand(m, from_ex)

    import_block_ex.head === :block || error("Expecting a block.")
    export_expr = Expr(:export)

    # unpack all the import statements and construct an export expression with all the imported
    # symbols.
    for import_ex in import_block_ex.args
        import_ex.head === :import || error("Expecting only import statements in the block.")
        for symbol_import_ex in import_ex.args
            symbol_import_ex.head === :(.) || error("Only individual imports handled so far")
            sym = last(symbol_import_ex.args)
            push!(export_expr.args, sym)
        end
    end

    # augment the final expression: first import, then export all the symbol
    return Expr(:block, import_block_ex, export_expr)
end

end

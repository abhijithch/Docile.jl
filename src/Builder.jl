"""
$(moduleheader())

Convert from abstract documentation tree defined by `Docile.DocTree` to different formats.

$(exports())
"""
module Builder

using ..Utilities

import ..DocTree

"""
    EXTERNAL_FILES

List of files that, if found in `source`, are written to a preset destination rather that
the `build` directory.
"""
const EXTERNAL_FILES = Dict(
    "README.md" => joinpath("..", "README.md"),
)

"""
    FORMATS

Valid output formats.
"""
const FORMATS = Dict(
    :markdown => ("md", MIME"text/markdown"()),
    :html     => ("html", MIME"text/html"()),
)

"""
    makedocs()

Generate markdown documentation from templated files.

**Keyword Arguments:**

``source = "src"``

Directory to collect markdown files from. The provided path is treated as being relative to
the directory in which the build script is run.

``build = "build"``

Destination directory for output files. As with ``source`` the path is relative to the build
script's directory.

``clean = false``

Should the build directory be deleted before building? ``external`` files are not affected
by this.

``verbose = true``

Print information about build process to terminal. On by default.

``external = $(EXTERNAL_FILES)``

User-defined files that, if found in ``source``, will be written to the provided paths
rather than the default in ``build``. ``makedocs`` writes ``README.md`` files to the parent
folder by default. This can be disabled by setting ``external = Dict()``.

**Usage:**

Import ``Docile`` and the modules that should be documented. Then call ``makedocs`` with any
additional settings that are needed.

```jl
using Docile, MyModule
makedocs()                   # Without customisations.
makedocs(source = "../docs") # With source folder ``docs``.
makedocs(clean = true)       # Clean build directory before building.
```
"""
function makedocs(;
    source   = "source",
    build    = "build",
    format   = :markdown,
    clean    = false,
    verbose  = true,
    external = EXTERNAL_FILES,
    )
    # Setup working directory as the same as the script that called `makedocs()`.
    cd(Base.source_dir()) do
        # Clean out old files in build directory.
        if clean && isdir(build)
            msg("removing old files.", verbose)
            rm(build, recursive = true)
        end
        # Find new ones in source directory.
        msg("finding source files.", verbose)
        input = files(x -> endswith(x, ".md"), source)
        # Exit early when there are no source files.
        isempty(input) && (warn("no source files found."); return)
        # Calculate file extension and mimetype.
        ext, mime = get(FORMATS, format, FORMATS[:markdown])
        msg("calculating file mapping.", verbose)
        # Generate file mapping from source to destination.
        mapping = []
        width = maximum(map(length, input))
        for each in input
            file = relpath(each, source)
            out  = extension(get(external, file, joinpath(build, file)), ext)
            dir  = dirname(out)
            isdir(dir) || mkpath(dir)
            verbose && println(" + ", rpad("$each", width), " --> ", out)
            push!(mapping, (each, out))
        end
        msg("building document tree.", verbose)
        # Setup correct root environment using given files. Output all content.
        root = DocTree.Root(mapping, mime)
        msg("expanding documentation nodes.", verbose)
        DocTree.expand!(root)
        msg("writing files.", verbose)
        writefile(root)
    end
end

import ..DocTree: Root, File, Node, Chunk

"""
    writefile(root)

Output a documentation tree to file.
"""
function writefile(root :: Root)
    for file in root.files
        writefile(root, file)
    end
end

function writefile(root :: Root, file :: File)
    open(file.output, "w") do buffer
        writefile(buffer, root, file)
    end
end

function writefile(io :: IO, root :: Root, file :: File)
    println(io, comment(root.mime, "Generated by Docile.jl | $(now())"))
    for node in file.nodes
        writefile(io, root, file, node)
    end
end

function writefile(io :: IO, root :: Root, file :: File, node :: Node)
    for chunk in node.chunks
        writefile(io, root, file, node, chunk)
    end
end

function writefile(io :: IO, root :: Root, file :: File, node :: Node, chunk :: Chunk)
    exec(chunk.name, io, root, file, node, chunk)
end


let T = Dict()
    global define, exec
    define(f, n) = haskey(T, n) ? error(":$n already defined.") : (T[n] = f)
    exec(n, args...) = haskey(T, n) ? T[n](args...) : error(":$n writer not defined.")
end

define((args...) -> error("cannot displat nested doc."), :docs)

define((args...) -> nothing, :module)

define(:esc) do io, root, file, node, chunk
    writemime(io, root.mime, Markdown.parse(chunk.text))
end

define(:break) do io, root, file, node, chunk
    print(io, "\n\n")
end

for sym in (:anchor, :ref, :code, :repl)
    @eval define($(Meta.quot(sym))) do io, root, file, node, chunk
        print(io, chunk.text)
    end
end


extension(file, ext) = string(splitext(file)[1], ".", ext)

comment(:: MIME"text/markdown", str) = "<!-- $(str) -->"
comment(:: MIME"text/html", str)     = "<!-- $(str) -->"

end

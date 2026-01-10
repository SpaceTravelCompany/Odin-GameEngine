## Markup rules

The generator uses simple markup rules to generate more structured documentation such as code blocks or examples.

### Blocks

1. A line starting with `Example:` will make subsequent lines that are indented with a tab a code block
2. A line starting with `Output:` or `Possible Output:` will make subsequent lines that are indented with a tab a block to note the output of the example
3. Indenting lines with a tab will wrap the indented lines with a preformatted tag (&lt;pre&gt;&lt;/pre&gt;)
4. The strings `Inputs:` and `Returns:` are automatically made bold as a convention for input and output of a procedure

There can be only 1 example, and only 1 output (or possible output) block in a doc block.

To make these work, you should not use a doc block with lines that start with spaces or stars or anything.
The convention is doc blocks like the following:

```odin
/*
Whether the given string is "example"

**Does not allocate**

Inputs:
- bar: The string to check

Returns:
- ok: A boolean indicating whether bar is "example"

Example:
	foo("example")
	foo("bar")

Output:
	true
	false
*/
foo :: proc(bar: string) -> (ok: bool) {}
```

### Inline

1. Inline code blocks are started and ended with a single \`, example: `code`
2. Links are created by 2 brackets, followed by the text, followed by a semi-colon, followed by 2 closing brackets, example: [[Example;https://example.com]]
3. Bold text is started and ended with 2 stars, example: **Foo**
4. Italic text is started and ended with 1 star, example: *Foo*
5. Starting line with a `-` makes the line a list item

## Using this to generate documentation for your packages

It is possible to generate a website similar to pkg.odin-lang.org for your packages.

To do this there is a config file you can reference as the second argument to this program.

Steps:

1. Build this project: `odin build . -out:odin-doc`
2. Just like `examples/all` linked above, create a file like this for the packages you want documented
3. Create the `.odin-doc` file: `odin doc path-to-step-1.odin -file -all-packages -doc-format`
4. Create a configuration file, explained below
5. Go into the directory where the docs should be generated, `website/static` for example
6. Generate the documentation by invoking the binary of step 1: `odin-doc path-to-.odin-doc path-to-config.json`

The directory you did step 6 in should now contain a html structure for any package that you referenced, and the packages it references.
You can now upload this to a static site host like GitHub pages.

- https://github.com/odin-lang/pkg.odin-lang.org - README
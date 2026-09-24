# Third-Party Notices

RADAR's Go binary incorporates the following modules:

| Module | Version | Copyright | License |
| --- | --- | --- | --- |
| `github.com/wI2L/jsondiff` | 0.7.1 | Copyright (c) 2020-2025 William Poussier &lt;william.poussier@gmail.com&gt; | MIT |
| `github.com/tidwall/gjson` | 1.18.0 | Copyright (c) 2016 Josh Baker | MIT |
| `github.com/tidwall/match` | 1.1.1 | Copyright (c) 2016 Josh Baker | MIT |
| `github.com/tidwall/pretty` | 1.2.1 | Copyright (c) 2017 Josh Baker | MIT |
| `github.com/tidwall/sjson` | 1.2.5 | Copyright (c) 2016 Josh Baker | MIT |

The version list is derived from `go.mod`. The corresponding integrity records are in `go.sum`.

## MIT License Text

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

## External Tools

Go, OPA, Kubernetes, kubectl, Minikube, Argo CD, Docker, Git, Git LFS, jq,
ShellCheck, PyYAML, bcrypt, and shell utilities are separate tools used for
development or execution. The optional bootstrap retrieves pinned tools into an
ignored local directory; they are not committed to the repository or
redistributed in RADAR's source-built release archive and remain governed by
their own licenses. Their names identify interoperability and do not imply
endorsement.

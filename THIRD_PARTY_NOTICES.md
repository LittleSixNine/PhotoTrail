# Third-party notices for PhotoTrail additions

PhotoTrail also incorporates conservative matching behavior derived from the
author's earlier PhotoTrail prototype. That source is MIT licensed; the merged
Swift implementation was rewritten for this application and its existing tests.

The forward coordinate formula in `Packages/Coords/Sources/Coords/CoordinateTransform.swift`
is adapted from [wandergis/coordtransform](https://github.com/wandergis/coordtransform).
The country rectangle and the one-step inverse are not used as geographic authority.

## coordtransform — MIT License

Copyright (c) 2015 记忆的残骸

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

## AMap

AMap JS API is loaded online from the official service, not vendored. Its use
is subject to AMap's service terms and the developer's own credentials and quota.
No AMap approval of the local inverse formula or its accuracy is implied.

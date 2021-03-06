# Copyright 2016 The Bazel Authors. All rights reserved.
# Copyright 2021 Zendesk. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""This rule was largely based on the core Bazel rule for
http_archives
https://github.com/bazelbuild/bazel/blob/6ec54ee8b8c0e712f4d0b56678471cabaa17b2c3/tools/build_defs/repo/http.bzl
"""

load(
    "@bazel_tools//tools/build_defs/repo:utils.bzl",
    "patch",
    "update_attrs",
    "workspace_and_buildfile",
)

def _github_release_archive_impl(ctx):
    """Implementation of the http_archive rule."""
    if ctx.attr.build_file and ctx.attr.build_file_content:
        fail("Only one of build_file and build_file_content can be provided.")

    release_url = "https://api.github.com/repos/%s/%s/releases/tags/%s" % (ctx.attr.owner, ctx.attr.repo, ctx.attr.tag)
    release_json_path = ctx.path("_release.json")

    cmd = [
        "curl",
        "--silent",
        "-n",
        "-L",
        "--output",
        release_json_path,
        release_url,
    ]
    ctx.execute(cmd, quiet = False)

    release = json.decode(ctx.read(release_json_path))
    ctx.delete(release_json_path)

    assets = [
        asset
        for asset in release["assets"]
        if asset["name"] == ctx.attr.asset_name
    ]

    if len(assets) < 1:
        fail("Couldn't find an asset matching %s" % ctx.attr.asset_name)
    else:
        asset = assets[0]

    # Download and extract
    download_path = ctx.path(asset["name"])
    cmd = [
        "curl",
        "--silent",
        "-n",
        "-L",
        "--header",
        "Accept: application/octet-stream",
        "--output",
        download_path,
        asset["url"],
    ]
    ctx.execute(cmd, quiet = False)
    ctx.extract(download_path, stripPrefix = ctx.attr.strip_prefix)
    ctx.delete(download_path)

    workspace_and_buildfile(ctx)
    patch(ctx)

    return update_attrs(ctx.attr, _github_release_archive_attrs.keys(), {})

_github_release_archive_attrs = {
    "owner": attr.string(
        doc =
            """""",
    ),
    "repo": attr.string(
        doc =
            """""",
    ),
    "tag": attr.string(
        doc =
            """""",
    ),
    "asset_name": attr.string(
        doc =
            """""",
    ),
    "sha256": attr.string(
        doc = """The expected SHA-256 of the file downloaded.
This must match the SHA-256 of the file downloaded. _It is a security risk
to omit the SHA-256 as remote files can change._ At best omitting this
field will make your build non-hermetic. It is optional to make development
easier but should be set before shipping.""",
    ),
    "netrc": attr.string(
        doc = "Location of the .netrc file to use for authentication",
    ),
    "strip_prefix": attr.string(
        doc = """A directory prefix to strip from the extracted files.
Many archives contain a top-level directory that contains all of the useful
files in archive. Instead of needing to specify this prefix over and over
in the `build_file`, this field can be used to strip it from all of the
extracted files.
For example, suppose you are using `foo-lib-latest.zip`, which contains the
directory `foo-lib-1.2.3/` under which there is a `WORKSPACE` file and are
`src/`, `lib/`, and `test/` directories that contain the actual code you
wish to build. Specify `strip_prefix = "foo-lib-1.2.3"` to use the
`foo-lib-1.2.3` directory as your top-level directory.
Note that if there are files outside of this directory, they will be
discarded and inaccessible (e.g., a top-level license file). This includes
files/directories that start with the prefix but are not in the directory
(e.g., `foo-lib-1.2.3.release-notes`). If the specified prefix does not
match a directory in the archive, Bazel will return an error.""",
    ),
    "type": attr.string(
        doc = """The archive type of the downloaded file.
By default, the archive type is determined from the file extension of the
URL. If the file has no extension, you can explicitly specify one of the
following: `"zip"`, `"jar"`, `"war"`, `"tar"`, `"tar.gz"`, `"tgz"`,
`"tar.xz"`, or `tar.bz2`.""",
    ),
    "patches": attr.label_list(
        default = [],
        doc =
            "A list of files that are to be applied as patches after " +
            "extracting the archive. By default, it uses the Bazel-native patch implementation " +
            "which doesn't support fuzz match and binary patch, but Bazel will fall back to use " +
            "patch command line tool if `patch_tool` attribute is specified or there are " +
            "arguments other than `-p` in `patch_args` attribute.",
    ),
    "patch_tool": attr.string(
        default = "",
        doc = "The patch(1) utility to use. If this is specified, Bazel will use the specifed " +
              "patch tool instead of the Bazel-native patch implementation.",
    ),
    "patch_args": attr.string_list(
        default = ["-p0"],
        doc =
            "The arguments given to the patch tool. Defaults to -p0, " +
            "however -p1 will usually be needed for patches generated by " +
            "git. If multiple -p arguments are specified, the last one will take effect." +
            "If arguments other than -p are specified, Bazel will fall back to use patch " +
            "command line tool instead of the Bazel-native patch implementation. When falling " +
            "back to patch command line tool and patch_tool attribute is not specified, " +
            "`patch` will be used.",
    ),
    "patch_cmds": attr.string_list(
        default = [],
        doc = "Sequence of Bash commands to be applied on Linux/Macos after patches are applied.",
    ),
    "patch_cmds_win": attr.string_list(
        default = [],
        doc = "Sequence of Powershell commands to be applied on Windows after patches are " +
              "applied. If this attribute is not set, patch_cmds will be executed on Windows, " +
              "which requires Bash binary to exist.",
    ),
    "build_file": attr.label(
        allow_single_file = True,
        doc =
            "The file to use as the BUILD file for this repository." +
            "This attribute is an absolute label (use '@//' for the main " +
            "repo). The file does not need to be named BUILD, but can " +
            "be (something like BUILD.new-repo-name may work well for " +
            "distinguishing it from the repository's actual BUILD files. " +
            "Either build_file or build_file_content can be specified, but " +
            "not both.",
    ),
    "build_file_content": attr.string(
        doc =
            "The content for the BUILD file for this repository. " +
            "Either build_file or build_file_content can be specified, but " +
            "not both.",
    ),
    "workspace_file": attr.label(
        doc =
            "The file to use as the `WORKSPACE` file for this repository. " +
            "Either `workspace_file` or `workspace_file_content` can be " +
            "specified, or neither, but not both.",
    ),
    "workspace_file_content": attr.string(
        doc =
            "The content for the WORKSPACE file for this repository. " +
            "Either `workspace_file` or `workspace_file_content` can be " +
            "specified, or neither, but not both.",
    ),
}

github_release_archive = repository_rule(
    implementation = _github_release_archive_impl,
    attrs = _github_release_archive_attrs,
    doc =
        """Downloads a Bazel repository as a compressed archive file, decompresses it,
and makes its targets available for binding.
It supports the following file extensions: `"zip"`, `"jar"`, `"war"`, `"tar"`,
`"tar.gz"`, `"tgz"`, `"tar.xz"`, and `tar.bz2`.
Examples:
  Suppose the current repository contains the source code for a chat program,
  rooted at the directory `~/chat-app`. It needs to depend on an SSL library
  which is available from github_release://example.com/openssl.zip. This `.zip` file
  contains the following directory structure:
  ```
  WORKSPACE
  src/
    openssl.cc
    openssl.h
  ```
  In the local repository, the user creates a `openssl.BUILD` file which
  contains the following target definition:
  ```python
  cc_library(
      name = "openssl-lib",
      srcs = ["src/openssl.cc"],
      hdrs = ["src/openssl.h"],
  )
  ```
  Targets in the `~/chat-app` repository can depend on this target if the
  following lines are added to `~/chat-app/WORKSPACE`:
  ```python
  load("@bazel_tools//tools/build_defs/repo:github_release.bzl", "github_release_archive")
  github_release_archive(
      name = "my_ssl",
      urls = ["github_release://example.com/openssl.zip"],
      sha256 = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
      build_file = "@//:openssl.BUILD",
  )
  ```
  Then targets would specify `@my_ssl//:openssl-lib` as a dependency.
""",
)

#!/usr/bin/env python3
# Ported from OSS-Fuzz projects/defusedxml/fuzz_etree_parse.py (Apache-2.0).
# instrument_imports (not instrument_all) keeps startup fast; DefusedXmlException is defusedxml's
# INTENDED defense signal on hostile input, so it is expected, not a defect.
"""Targets the parse function"""
import io
import sys

import atheris

with atheris.instrument_imports(include=["defusedxml", "xml"]):
    import xml.etree.ElementTree
    import defusedxml.common
    from defusedxml.ElementTree import parse


def TestOneInput(data):
    fdp = atheris.FuzzedDataProvider(data)
    in_mem_file = io.StringIO(fdp.ConsumeUnicodeNoSurrogates(sys.maxsize))
    try:
        parse(in_mem_file)
    except (xml.etree.ElementTree.ParseError, defusedxml.common.DefusedXmlException):
        pass


def main():
    atheris.Setup(sys.argv, TestOneInput)
    atheris.Fuzz()


if __name__ == "__main__":
    main()

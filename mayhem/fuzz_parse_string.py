#!/usr/bin/env python3
# Ported from OSS-Fuzz projects/defusedxml/fuzz_parse_string.py (Apache-2.0).
# instrument_imports (not instrument_all) keeps startup fast; DefusedXmlException / SAXParseException
# are defusedxml's INTENDED defense signals on hostile input, so they are expected, not defects.
"""Targets parseString"""
import sys

import atheris

with atheris.instrument_imports(include=["defusedxml", "xml"]):
    import xml.parsers.expat
    from xml.sax import SAXParseException
    import defusedxml.common
    from defusedxml.pulldom import parseString as pulldom_parseString
    from defusedxml.minidom import parseString as minidom_parseString
    from defusedxml.expatbuilder import parseString as expatbuilder_parseString


def TestOneInput(data):
    fdp = atheris.FuzzedDataProvider(data)
    try:
        pulldom_parseString(fdp.ConsumeUnicodeNoSurrogates(sys.maxsize))
        minidom_parseString(fdp.ConsumeUnicodeNoSurrogates(sys.maxsize))
        expatbuilder_parseString(fdp.ConsumeUnicodeNoSurrogates(sys.maxsize))
    except (
        xml.parsers.expat.ExpatError,
        defusedxml.common.DefusedXmlException,
        SAXParseException,
    ):
        pass


def main():
    atheris.Setup(sys.argv, TestOneInput)
    atheris.Fuzz()


if __name__ == "__main__":
    main()

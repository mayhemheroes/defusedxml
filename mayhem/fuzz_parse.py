#! /usr/bin/python3
import xml.etree.ElementTree

import atheris
import sys
import io

with atheris.instrument_imports():
    import defusedxml.pulldom
    import defusedxml.ElementTree
    import defusedxml.common
    import defusedxml.expatreader
    import defusedxml.expatbuilder


def TestOneInput(data):
    fdp = atheris.FuzzedDataProvider(data)
    # Get enough bytes for each possible harness
    total_byte_count = len(data)
    harness_bytes = []
    for _ in range(4):
        harness_bytes.append(fdp.ConsumeBytes(total_byte_count // 4))
    try:
        # Parse the input as a string
        defusedxml.pulldom.parseString(str(harness_bytes[0]))

        # Parse file
        defusedxml.ElementTree.parse(io.BytesIO(harness_bytes[1]))

        # Use expat
        builder = defusedxml.expatbuilder.DefusedExpatBuilder()
        builder.parseString(str(harness_bytes[2]))
        builder.parseFile(io.BytesIO(harness_bytes[3]))

    except (defusedxml.common.DefusedXmlException, xml.etree.ElementTree.ParseError):
        pass


def main():
    atheris.Setup(sys.argv, TestOneInput)
    atheris.Fuzz()


if __name__ == "__main__":
    main()

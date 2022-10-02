#! /usr/bin/python3
import pdb
import atheris
import sys

with atheris.instrument_imports():
    from defusedxml.pulldom import parseString


def TestOneInput(data):
    fdp = atheris.FuzzedDataProvider(data)
    parse_str = fdp.ConsumeString(atheris.ALL_REMAINING)
    parseString(parse_str)


def main():
    atheris.Setup(sys.argv, TestOneInput)
    atheris.Fuzz()


if __name__ == "__main__":
    main()

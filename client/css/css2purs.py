#!/usr/bin/python3
import re
import fileinput

# Usage:
# cat tailwind.css | ./css2purs.py > Tailwind.purs

# vim Regex
# /^\s*\.[^ ]*

# Using list rather than set to preserve sorted order
# Assuming that duplicates are always adjacent
cssNames = []

def process(line):
    # Example input:
    # line = '    .-sm\:-space-y-0-w-1\/2:hover {'
    regName = re.compile('^\s*\.([^ ]*?[^\\\\])(:.*)? .*$')

    m = regName.match(line)

    if m:
        escaped = m.group(1)
        # Just escaped class name
        # -sm\:-space-y-0-w-1\/2

        cssStr = escaped.replace('\\', '')
        # Remove escaped symbols - this is the CSS string
        # -sm:-space-y-0-w-1/2

        # don't add duplicates
        # assuming always adjacent
        if len(cssNames) and cssNames[-1] == cssStr:
            return

        cssNames.append(cssStr)

def cssToPs(cssStr):
    # Conversion to PureScript-compatible name
    # Must remove symbols

    def negRepl(m):
        return m.group(1) + 'neg' + m.group(3).upper()
    negSub = re.sub(r'(^|:)(-)(.)', negRepl, cssStr)
    # Replace leading dashes (used to represent negatives) with 'neg'
    # Camel-case for next word
    # negSm:negSpace-y-0-w-1/2

    colonDivSub = negSub.replace(':', '-').replace('/', 'd')
    # replace colon separator with dash
    # replace division sign for fractions with 'd'
    # negSm-negSpace-y-0-w-1d2

    def dashRepl(m):
        return m.group(1).upper()
    dashSub = re.sub(r'-(.)', dashRepl, colonDivSub)
    # Convert dash-separator to camelCase
    # negSmNegSpaceY0W1d2

    # Debug prints
    # print('cssStr', cssStr)
    # print(escaped)
    # print(negSub)
    # print(colonDivSub)
    # print(dashSub)

    psName = dashSub
    print()
    print('-- | ' + cssStr)
    print(psName + ' :: ClassName')
    print(psName + ' = ClassName "' + cssStr + '"')

for line in fileinput.input():
    process(line)

print('-- | Autogenerated from tailwind.css')
print('module Tailwind where')
print()
print('import Halogen.HTML.Core (ClassName(..))')

for cssName in cssNames:
    cssToPs(cssName)

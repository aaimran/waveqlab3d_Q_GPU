#!/usr/bin/env python3
from array import array
from pathlib import Path
from sys import argv, exit


dir1 = 'truth'
dir2 = 'data'
ngrid = 21
ntime = 46

prefix = argv[2]
path = argv[1]

_files = [(4, prefix+'_interface.S'),
          (3, prefix+'_interface.Svel'),
          # (1, prefix+'_interface.trup'),
          # (1, prefix+'_interface.state'),
          (9, prefix+'_interface.Uface'),
          (9, prefix+'_interface.Vface'),
          (6, prefix+'_interface.Uhat'),
          (6, prefix+'_interface.Vhat')]

for nfields, fname in _files:
    filenames = [Path(path, dir1, fname), Path(path, dir2, fname)]
    fields = []
    expected_values = ntime * nfields * ngrid * ngrid

    for name in filenames:
        values = array('f')
        with name.open('rb') as stream:
            values.fromfile(stream, expected_values)
        fields.append(values)

    max_difference = max(abs(actual - expected)
                         for expected, actual in zip(fields[0], fields[1]))
    if max_difference > 1.0e-3:
        print(fname, max_difference)
        exit(1)

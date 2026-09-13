# Illustrative synthetic example

These CSVs are **not real invoices**. They are a hand-built, fictional Hetzner
fleet (made-up servers, made-up amounts) so you can run the audit without a
Hetzner account:

```
./gelkao invoice audit -q -d examples
```

The numbers here are invented to demonstrate the tool and are unrelated to any
real account or to the figures cited in the blog write-up.

## example-volumes.tsv

A synthetic placement table in the format Hetzner support mails you
(`volume id / volume pool id / leaf`, tab separated):

```
./gelkao volume show < examples/example-volumes.tsv
./gelkao volume draw < examples/example-volumes.tsv
```

199 volumes, 36 leaves, 54 pools. Leaf and pool sizes are modelled on a real
fleet so the map looks like something you would actually get; every identifier
is invented. The largest leaf is arranged so the example generates every colour
the map can draw.

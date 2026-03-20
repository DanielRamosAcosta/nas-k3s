{
  partOf(name):: {
    metadata+: { labels+: { 'app.kubernetes.io/part-of': name } },
  },

  templatePartOf(name):: {
    spec+: { template+: { metadata+: { labels+: { 'app.kubernetes.io/part-of': name } } } },
  },
}

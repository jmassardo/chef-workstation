+++
title = "{{ replace .Name "-" " " | title }}"
draft = true

[menu]
  [menu.workstation]
    title = "{{ replace .Name "-" " " | title }}"
    identifier = "chef_workstation/{{ .Name }}.md {{ replace .Name "-" " " | title }}"
    parent = "chef_workstation"
    weight = 10
+++


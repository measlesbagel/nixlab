# Models

Weights live in one library on albipes (`services/model-library.nix`);
hosts keep local copies of the models they run (`services/model-sync.nix`).
A merge is what adds, swaps or removes a model.

## Add a model to the library

Pin it to a Hugging Face commit in `services/model-library.nix`:

```nix
homelab.models.library = {
  "org/name".rev = "<40-character commit>";
};
```

The current commit of a repo, without a token for public ones:

```console
git ls-remote https://huggingface.co/org/name HEAD
```

albipes downloads it in the background after the deploy into
`/tank/models/org/name`. Gated models need a read-scope token at
`op://homelab/huggingface/token`. Removing an entry deletes the model.

## Keep a copy on a host

List it in the host's file (it must be in the library):

```nix
homelab.models.local = [ "org/name" ];
```

The host deletes models it no longer lists, then copies the new ones into
`/var/lib/models/org/name`. The Sparks list the same models: leetzi
copies from the NAS (bound by its two-disk mirror), elegans from
leetzi over ConnectX-7 (bound by NVMe). Restarts and reboots copy
nothing.

A model is complete when its `.nixlab-revision` file exists, at the source
and locally alike; it is written last, so services that load a model should
wait for it.

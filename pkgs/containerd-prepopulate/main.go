// containerd-prepopulate imports docker-archive tarballs into containerd's
// on-disk storage format (content store + native snapshotter + boltdb metadata)
// WITHOUT requiring a running containerd daemon.
//
// This allows pre-populating an AMI with container images so k3s can start
// with images already available, eliminating the tarball import that normally
// happens on every boot.
//
// Usage: containerd-prepopulate -root /path/to/output -namespace k8s.io tarball1.tar tarball2.tar ...
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	"github.com/containerd/containerd/v2/core/content"
	"github.com/containerd/containerd/v2/core/images"
	"github.com/containerd/containerd/v2/core/images/archive"
	"github.com/containerd/containerd/v2/core/metadata"
	"github.com/containerd/containerd/v2/core/snapshots"
	contentlocal "github.com/containerd/containerd/v2/plugins/content/local"
	"github.com/containerd/containerd/v2/plugins/snapshots/native"
	"github.com/containerd/errdefs"
	"github.com/containerd/log"
	"github.com/containerd/containerd/v2/pkg/namespaces"
	ocispec "github.com/opencontainers/image-spec/specs-go/v1"
	bolt "go.etcd.io/bbolt"
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}
}

func run() error {
	rootDir := ""
	namespace := "k8s.io"
	var tarballs []string

	args := os.Args[1:]
	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "-root":
			i++
			rootDir = args[i]
		case "-namespace":
			i++
			namespace = args[i]
		default:
			tarballs = append(tarballs, args[i])
		}
	}

	if rootDir == "" {
		return fmt.Errorf("usage: containerd-prepopulate -root <dir> [-namespace <ns>] <tarball>...")
	}
	if len(tarballs) == 0 {
		return fmt.Errorf("no tarballs specified")
	}

	ctx := context.Background()
	ctx = log.WithLogger(ctx, log.L)
	ctx = namespaces.WithNamespace(ctx, namespace)

	// Create directory structure matching containerd's expected layout
	contentRoot := filepath.Join(rootDir, "io.containerd.content.v1.content")
	snapshotRoot := filepath.Join(rootDir, "io.containerd.snapshotter.v1.native")
	metadataDir := filepath.Join(rootDir, "io.containerd.metadata.v1.bolt")
	metadataPath := filepath.Join(metadataDir, "meta.db")

	for _, dir := range []string{contentRoot, snapshotRoot, metadataDir} {
		if err := os.MkdirAll(dir, 0755); err != nil {
			return fmt.Errorf("creating directory %s: %w", dir, err)
		}
	}

	// Initialize the local content store (stores image blobs as files)
	cs, err := contentlocal.NewStore(contentRoot)
	if err != nil {
		return fmt.Errorf("creating content store: %w", err)
	}

	// Initialize the native snapshotter (unpacks layers as plain directories)
	sn, err := native.NewSnapshotter(snapshotRoot)
	if err != nil {
		return fmt.Errorf("creating native snapshotter: %w", err)
	}
	defer sn.Close()

	// Open boltdb for metadata
	bdb, err := bolt.Open(metadataPath, 0644, nil)
	if err != nil {
		return fmt.Errorf("opening metadata db: %w", err)
	}

	// Create metadata DB wrapping content store and snapshotter
	mdb := metadata.NewDB(bdb, cs, map[string]snapshots.Snapshotter{
		"native": sn,
	})
	if err := mdb.Init(ctx); err != nil {
		return fmt.Errorf("initializing metadata db: %w", err)
	}

	// Get namespaced stores from metadata DB
	imgStore := metadata.NewImageStore(mdb)
	mcs := mdb.ContentStore()

	// Import each tarball
	for _, tarball := range tarballs {
		fmt.Printf("Importing %s...\n", tarball)

		f, err := os.Open(tarball)
		if err != nil {
			return fmt.Errorf("opening tarball %s: %w", tarball, err)
		}

		// ImportIndex returns the index descriptor for the imported content
		desc, err := archive.ImportIndex(ctx, mcs, f)
		f.Close()
		if err != nil {
			return fmt.Errorf("importing %s: %w", tarball, err)
		}

		// Read the index to get individual image manifests
		imgNames, err := registerImages(ctx, mcs, imgStore, desc, tarball)
		if err != nil {
			return fmt.Errorf("registering images from %s: %w", tarball, err)
		}
		for _, name := range imgNames {
			fmt.Printf("  registered: %s\n", name)
		}
	}

	// Close the database cleanly
	if err := bdb.Close(); err != nil {
		return fmt.Errorf("closing metadata db: %w", err)
	}

	fmt.Printf("Done. Pre-populated containerd store at %s\n", rootDir)
	return nil
}

// registerImages creates image records from an imported index descriptor.
func registerImages(ctx context.Context, cs content.Store, imgStore images.Store, desc ocispec.Descriptor, source string) ([]string, error) {
	var names []string

	// Read the index/manifest to find image references
	data, err := content.ReadBlob(ctx, cs, desc)
	if err != nil {
		// If we can't read it as an index, register the descriptor directly
		name := fmt.Sprintf("import-%s", filepath.Base(source))
		img := images.Image{
			Name:   name,
			Target: desc,
		}
		if _, err := imgStore.Create(ctx, img); err != nil && !errdefs.IsAlreadyExists(err) {
			return nil, err
		}
		return []string{name}, nil
	}

	// Try to parse as OCI index
	var index ocispec.Index
	if err := json.Unmarshal(data, &index); err == nil && len(index.Manifests) > 0 {
		for _, m := range index.Manifests {
			name := ""
			if m.Annotations != nil {
				name = m.Annotations[ocispec.AnnotationRefName]
				if name == "" {
					name = m.Annotations[images.AnnotationImageName]
				}
			}
			if name == "" {
				name = m.Digest.String()
			}

			img := images.Image{
				Name:   name,
				Target: m,
			}
			_, err := imgStore.Create(ctx, img)
			if err != nil {
				if errdefs.IsAlreadyExists(err) {
					_, err = imgStore.Update(ctx, img)
				}
				if err != nil {
					return nil, fmt.Errorf("registering %s: %w", name, err)
				}
			}
			names = append(names, name)
		}
		return names, nil
	}

	// Fall back: register the whole descriptor as a single image
	name := filepath.Base(source)
	img := images.Image{
		Name:   name,
		Target: desc,
	}
	if _, err := imgStore.Create(ctx, img); err != nil && !errdefs.IsAlreadyExists(err) {
		return nil, err
	}
	return []string{name}, nil
}

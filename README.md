# Device Mapper Test Suite

Tests device mapper kernel targets for Linux.

This test suite replaces the [thinp-test-suite package](https://github.com/jthornber/thinp-test-suite).
It switches to using Ruby 1.9, has an improved user interface and
configuration file, and tests more than just the thin provisioning
target.

# Installation

## RVM

I recommend you use [RVM](https://rvm.io/rvm/install) to manage your
Ruby installation.  It allows you to install many versions of Ruby
concurrently, and automatically switch between them depending on the
contents of a _.ruby-version_ file in your project's root directory.

The above link gives more details, but here's a quickstart:

    curl -L https://get.rvm.io | bash

**Make sure you follow the instructions at the end of the script
regarding setting your shell's environment.**

Now we need to install Ruby 2.5.3

    rvm install 2.5.3

### Ruby Index (_ri_)

If you wish to use ri to consult the Ruby Documentation (RDoc) for the newly
installed ruby then it will need to be generated

    rvm docs generate-ri

## Gems

Now we need to make sure the gem catalogue is up to date.
[Gems](http://rubygems.org/) are packaged Ruby libraries.

    gem update

Grab the [bundler] package, which will automatically install all our Ruby dependencies for us.

    gem install bundler

## Bundle

In the device-mapper-test-suite directory:

    bundle update

This should install all the ruby libraries we need.

## Other requirements

The tests use various tools which you'll need in your path (I don't
think this list is complete):

[thin-provisioning-tools](https://github.com/jthornber/thin-provisioning-tools),
dd, git,
[dt](http://www.scsifaq.org/RMiller_Tools/dt.html),
[iozone] (http://www.iozone.org/),
blktrace, bonnie++, fio

# Configuration

Now run *dmtest*.  The first time it's run it will set up a \~/.dmtest/
directory for you, and write an example config file (\~/.dmtest/config).

    profile :ssd do
      metadata_dev '/dev/vdb'
      data_dev '/dev/vdc'
    end
    
    profile :spindle do
      metadata_dev '/dev/vdd'
      data_dev '/dev/vde'
    end
    
    profile :mix do
      metadata_dev '/dev/vdb'
      data_dev '/dev/vde'
    end
    
    default_profile :ssd

The config file consists of one or more _profiles_ (these are selected
with the --profile command line switch).  Within each profile you have
to specify a device which is used to store thin provisioning metadata
and cache data on it.  Typically this should be a fast device such as
an SSD (or a logical volume allocated on an SSD of course).  The other
device should be a slower data device.

As you can see I normally use several profiles, depending on whether
I'm developing new code and want the tests to run quickly (:ssd),
testing a realistic set up (:mix), or just searching for those race
conditions that only appear when using slower devices (:spindle).

A metadata dev of 1G, and data dev of 4G is sufficient.  Some poorly
written tests use all of the data dev, no matter how big it is, so
will take longer to run with large volumes.

# Usage

    dmtest <cmd> <switches>*

## General options

### --suite

The tests are divided up into *suites*, which are specific to a
particular target.  Use the --suite switch to specify this:

    dmtest list --suite thin-provisioning

Options are:

* bcache
* cache
* enhance_io
* fake-discard
* infrastructure
* thin-benchmarking
* thin-provisioning

Though only *thin-provisioning* and *cache* are generally used.

### --profile

You can select the configuration profile using --profile.

    dmtest run --suite thin-provisioning --profile spindle -t /Creation/

## Listing tests

Use the list command get an idea of the tests that are available.

    dmtest list --suite thin-provisioning

    thin-provisioning
      BasicTests
        dd_benchmark
        ext4_weirdness
        overwrite_a_linear_device
        overwriting_various_thin_devices
      CreationTests
        create_lots_of_empty_thins
        create_lots_of_recursive_snaps
        create_lots_of_snaps
        huge_block_size
        largest_data_block_size_succeeds
        largest_dev_t_succeeds
        non_power_of_2_data_block_size_fails
        too_large_a_dev_t_fails
        too_large_data_block_size_fails
        too_small_a_metadata_dev_fails
        too_small_data_block_size_fails
      DeletionTests
        create_delete_cycle
        create_many_thins_then_delete_them
        delete_active_device_fails
        delete_thin
        ...

The indentation indicates the organisation of the tests by
suite/class/test.

You can specify an exact match for the class:

    dmtest list --suite thin-provisioning -t SnapshotTests
    
    thin-provisioning
      SnapshotTests
        break_sharing_ext4
        break_sharing_xfs
        create_snap_ext4
        create_snap_xfs
        many_snapshots_of_same_volume
        parallel_io_to_shared_thins
        ref_count_tree
        thin_overwrite_ext4
        thin_overwrite_xfs

Or you can use a regular expression for the class:

    dmtest list --suite thin-provisioning -t /Creation\|Deletion/
    
    thin-provisioning
      CreationTests
        create_lots_of_empty_thins
        create_lots_of_recursive_snaps
        create_lots_of_snaps
        huge_block_size
        largest_data_block_size_succeeds
        largest_dev_t_succeeds
        non_power_of_2_data_block_size_fails
        too_large_a_dev_t_fails
        too_large_data_block_size_fails
        too_small_a_metadata_dev_fails
        too_small_data_block_size_fails
      DeletionTests
        create_delete_cycle
        create_many_thins_then_delete_them
        delete_active_device_fails
        delete_thin
        delete_unknown_devices
        rolling_create_delete

Selecting individual tests is similarly done via the -n switch:

    dmtest list --suite thin-provisioning -n /create/
    
    thin-provisioning
      CreationTests
        create_lots_of_empty_thins
        create_lots_of_recursive_snaps
        create_lots_of_snaps
      DeletionTests
        create_delete_cycle
        create_many_thins_then_delete_them
        rolling_create_delete
      MultiplePoolTests
        two_pools_can_create_thins
      ReadOnlyTests
        cant_create_new_thins
        create_read_only
      SnapshotTests
        create_snap_ext4
        create_snap_xfs

Currently you can use multiple selectors.  I'll add at some point.

## Running tests

Once you're happy with the subset of tests that you're listing, you should run them:

dmtest run --suite thin-provisioning -n /create/

    Loaded suite thin-provisioning
    Started
    test_create_lots_of_empty_thins(CreationTests): .
    test_create_lots_of_recursive_snaps(CreationTests): .
    test_create_lots_of_snaps(CreationTests): .
    test_create_delete_cycle(DeletionTests): .
    test_create_many_thins_then_delete_them(DeletionTests): .
    test_rolling_create_delete(DeletionTests): .
    test_two_pools_can_create_thins(MultiplePoolTests): .
    test_cant_create_new_thins(ReadOnlyTests): E
    test_create_read_only(ReadOnlyTests): F
    test_create_snap_ext4(SnapshotTests): .
    test_create_snap_xfs(SnapshotTests): .

Generally the tests run quietly.  Just the test name will be printed,
and a character to indicate the outcome of the test:

    . - Success
    F - The test failed
    E - There's a bug in the test itself

Once all the tests have run you'll get some Ruby back traces for the
failing and erroring tests.

A full log of each test can be found in ~/.dmtest/log/\<class\>_\<test\>.log

## Serving results

Digging around in log files can be tedious.  So after every test run,
dmtest generates a set of html reports that can be found in
~/.dmtest/reports.  Either open them directly, or get dmtest to fire
up a little http server:

    dmtest serve --port 1234

Then point your browser at http://localhost:1234

The default port is 8080.  These reports summarise which tests have
passed or failed, when the tests were last run, and gives access to
markedup versions of the logs.

Generally I run the server all the time in the background; it will
automatically pick up any newly generated reports.

## Generating reports

Generating test reports happens automatically as part of the *run*
command.  But there are times when you want to generate the reports by
hand (eg, a test bug caused *dmtest* to exit before generating the
reports).

    dmtest generate

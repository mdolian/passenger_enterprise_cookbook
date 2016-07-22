# Passenger Enterprise Cookbook

## General

This cookbook will install and configure Passenger Enterprise standalone on Engine Yard Cloud (AWS) application instances.  It must be used in conjunction with the "Nginx Only" stack option for the application server layer.  This feature can be enabled by Engine Yard staff.   You also need a valid Passenger Enterprise license obtained through Phusion.  To use this cookbook, simply add your license file and include it in the main recipe (see below).

## Attributes

The following attributes are configurable in the cookbook:

* version - The version to install
* password - Your password to the download site
* port - The port to run standalone passenger on

Defaults:

```
passenger_enterprise :version => "4.0.37",
                     :password => "<REMOVED>",
                     :port => "5000"
```

## The license file

Make sure your license file is in:

  cookbooks/passenger_enterprise/files/default/passenger-enterprise-license-{staging,production}

## Nginx Only Feature

Engine Yard must turn on the "Nginx Only" feature on your account.  When creating the Passenger Enterprise environment, you must select "Nginx Only" as the application server.  This will tell our platform to not configure an application server so that you may drop whichever application server you want into place.


## Usage

Add to cookbooks/main/recipes/default.rb:  

```
include_recipe "passenger_enterprise"
```

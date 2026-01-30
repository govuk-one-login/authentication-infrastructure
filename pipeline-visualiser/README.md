# Pipeline Visualiser

Pipeline Visualiser provides cross-account visiblity of AWS CodePipeline pipelines, because that's not a feature of the product at the time of writing (March 2024).

## Where can I view it

https://authpipeline.signin.build.account.gov.uk/

## How does it work

It assumes each of the roles described in `config.yml`, reads from the CodePipeline API, and then collates and presents that information in the GOV.UK Design System style.

## How can I run it locally ?

### With real data

To be able to run locally  with real data, you must have at least SSO readonly permission in AWS account  in `config.yml`

To run the code successfully

```
bundle install
make run
```

This will SSO to all aws account which has permission in `config.yml`.

@description('Name of the Log Analytics Workspace')
param logAnalyticsAccountName string

@description('Name of the Data Collection Rule')
param dataCollectionRuleName string

@description('Service Principal Ids to be assigned the Metrics Publisher role on the Data Collection Rule')
param metricsPublisherPrincipals array

@description('Location where the resources will be deployed')
param location string

@description('Tags to be assigned to the created resources')
param resourceTags object

resource logAnalyticsAccount 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsAccountName
  location: location
  tags: resourceTags
  properties: {
    retentionInDays: 30
    sku: {
      name: 'PerGB2018'
    }
  }
}

resource workspaceTable 'Microsoft.OperationalInsights/workspaces/tables@2025-02-01' = {
  parent: logAnalyticsAccount
  name: 'SCEPman_CL'
  properties: {
    totalRetentionInDays: 30
    plan: 'Analytics'
    schema: {
      name: 'SCEPman_CL'
      columns: [
        {
          name: 'TimeGenerated'
          type: 'datetime'
        }
        {
          name: 'Timestamp'
          type: 'string'
        }
        {
          name: 'Level'
          type: 'string'
        }
        {
          name: 'Message'
          type: 'string'
        }
        {
          name: 'Exception'
          type: 'string'
        }
        {
          name: 'TenantIdentifier'
          type: 'string'
        }
        {
          name: 'RequestUrl'
          type: 'string'
        }
        {
          name: 'UserAgent'
          type: 'string'
        }
        {
          name: 'LogCategory'
          type: 'string'
        }
        {
          name: 'EventId'
          type: 'string'
        }
        {
          name: 'Hostname'
          type: 'string'
        }
        {
          name: 'WebsiteHostname'
          type: 'string'
        }
        {
          name: 'WebsiteSiteName'
          type: 'string'
        }
        {
          name: 'WebsiteSlotName'
          type: 'string'
        }
        {
          name: 'BaseUrl'
          type: 'string'
        }
        {
          name: 'TraceIdentifier'
          type: 'string'
        }
      ]
    }
    retentionInDays: 30
  }
}

resource dataCollectionRule 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: dataCollectionRuleName
  location: location
  tags: resourceTags
  kind: 'Direct'
  properties: {
    description: 'Data Collection Rule for SCEPman logs'
    streamDeclarations: {
      'Custom-SCEPmanLogs': {
        columns: [
          {
            name: 'Timestamp'
            type: 'string'
          }
          {
            name: 'Level'
            type: 'string'
          }
          {
            name: 'Message'
            type: 'string'
          }
          {
            name: 'Exception'
            type: 'string'
          }
          {
            name: 'TenantIdentifier'
            type: 'string'
          }
          {
            name: 'RequestUrl'
            type: 'string'
          }
          {
            name: 'UserAgent'
            type: 'string'
          }
          {
            name: 'LogCategory'
            type: 'string'
          }
          {
            name: 'EventId'
            type: 'string'
          }
          {
            name: 'Hostname'
            type: 'string'
          }
          {
            name: 'WebsiteHostname'
            type: 'string'
          }
          {
            name: 'WebsiteSiteName'
            type: 'string'
          }
          {
            name: 'WebsiteSlotName'
            type: 'string'
          }
          {
            name: 'BaseUrl'
            type: 'string'
          }
          {
            name: 'TraceIdentifier'
            type: 'string'
          }
          {
            name: 'TimeGenerated'
            type: 'datetime'
          }
        ]
      }
    }
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: logAnalyticsAccount.id
          name: 'SCEPmanLogAnalyticsDestination'
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          'Custom-SCEPmanLogs'
        ]
        destinations: [
          'SCEPmanLogAnalyticsDestination'
        ]
        outputStream: 'Custom-SCEPman_CL'
      }
    ]
  }
}

resource roleAssignment_law_metricspublisherPrincipals 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for item in metricsPublisherPrincipals: {
    scope: dataCollectionRule
    name: guid('roleAssignment-law-${item}-metricspublisher')
    properties: {
      roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', '3913510d-42f4-4e42-8a64-420c390055eb') //3913510d-42f4-4e42-8a64-420c390055eb is Monitoring Metrics Publisher
      principalId: item
    }
  }
]

output dcrImmutableId string = dataCollectionRule.properties.immutableId
output dcrEndpointUri string = dataCollectionRule.properties.endpoints.logsIngestion

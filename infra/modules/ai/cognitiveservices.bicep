param name string
param location string = resourceGroup().location
param tags object = {}
param managedIdentityName string = ''
param deployments array = []
param kind string = 'OpenAI'
param sku object = {
  name: 'S0'
}
param deploymentCapacity int = 2
param vnetId string
param openaiSubnetName string = 'openai-subnet'
param privateEndpointName string = '${name}-pe'
param privateEndpointLocation string
param privateDnsZoneGroupName string = '${name}-pe-dns'

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' existing = {
  name: managedIdentityName
}

resource account 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: name
  location: location
  tags: union(tags, { 'azd-service-name': name })
  kind: kind
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    customSubDomainName: name
    virtualNetworkRules: [
      {
        id: '${vnetId}/subnets/${openaiSubnetName}'
      }
    ]
    publicNetworkAccess: 'Disabled'
  }
  sku: sku
}

@batchSize(1)
resource deployment 'Microsoft.CognitiveServices/accounts/deployments@2023-05-01' = [for deployment in deployments: {
  parent: account
  name: deployment.name
  properties: {
    model: deployment.model
    raiPolicyName: contains(deployment, 'raiPolicyName') ? deployment.raiPolicyName : null
  }
  sku: contains(deployment, 'sku') ? deployment.sku : {
    name: 'Standard'
    capacity: deploymentCapacity
  }
}]

resource openAiPrivateEndpoint 'Microsoft.Network/privateEndpoints@2021-05-01' = {
  name: privateEndpointName
  location: privateEndpointLocation 
  properties: {
    subnet: {
      id: '${vnetId}/subnets/${openaiSubnetName}' 
    }
    privateLinkServiceConnections: [
      {
        name: '${name}-plsc'
        properties: {
          privateLinkServiceId: account.id
          groupIds: [
            'account'
          ]
          requestMessage: 'Please approve the connection request.'
        }
      }
    ]
  }
  dependsOn: [
    account
  ]
}

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  name: 'privatelink.openai.azure.com'
}

resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-09-01' = {
  name: privateDnsZoneGroupName
  parent: openAiPrivateEndpoint
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelinkdns'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
}

output openAiName string = account.name
output openAiEndpointUri string = '${account.properties.endpoint}openai/'

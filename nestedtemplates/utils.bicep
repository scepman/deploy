// Function to convert colon-style variable names to underscore-separated variable names if deployOnLinux is true
@export()
func convertVariableNameToLinux(variableName string, deployOnLinux bool) string =>
  deployOnLinux ? replace(variableName, ':', '__') : variableName

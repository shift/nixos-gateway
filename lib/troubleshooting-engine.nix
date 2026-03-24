{ lib }:

{
  # Define decision tree node types
  nodeTypes = {
    check = "check"; # Automatic check
    question = "question"; # User input required
    action = "action"; # Remediation step
    result = "result"; # Final outcome
  };

  # Validate decision tree structure
  validateTree =
    tree:
    let
      hasRequiredFields = t: (t ? id) && (t ? title) && (t ? startNode) && (t ? nodes);
      hasNode = id: tree.nodes ? ${id};
      validateNode =
        id: node:
        (node ? type)
        && (
          if node.type == "check" || node.type == "question" then
            (node ? next) || (node ? yes && node ? no)
          else
            true
        );
      allNodesValid = lib.all (id: validateNode id tree.nodes.${id}) (lib.attrNames tree.nodes);
    in
    hasRequiredFields tree && allNodesValid;

  # Generate diagnostic script
  mkDiagnosticScript = pkgs: tree: ''
    #!${pkgs.runtimeShell}
    set -e

    # Colors
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m'

    echo -e "''${YELLOW}Starting Troubleshooting: ${tree.title}''${NC}"
    echo "----------------------------------------"

    CURRENT_NODE="${tree.startNode}"

    while [ "$CURRENT_NODE" != "END" ]; do
      case "$CURRENT_NODE" in
        ${lib.concatMapStringsSep "\n" (
          nodeId:
          let
            node = tree.nodes.${nodeId};
          in
          ''
            "${nodeId}")
              ${
                if node.type == "check" then
                  ''
                    echo -n "Checking: ${node.description}... "
                    if ${node.command}; then
                      echo -e "''${GREEN}OK''${NC}"
                      CURRENT_NODE="${node.pass or node.yes}"
                    else
                      echo -e "''${RED}FAIL''${NC}"
                      CURRENT_NODE="${node.fail or node.no}"
                    fi
                  ''
                else if node.type == "question" then
                  ''
                    echo -e "''${YELLOW}Question: ${node.text}''${NC}"
                    if [ -z "$DIAGNOSE_NON_INTERACTIVE" ]; then
                      read -p "[y/n]> " response
                    else
                       # Default to 'no' in non-interactive unless overridden
                       echo "Non-interactive default: no"
                       response="n"
                    fi

                    if [[ "$response" =~ ^[Yy] ]]; then
                      CURRENT_NODE="${node.yes}"
                    else
                      CURRENT_NODE="${node.no}"
                    fi
                  ''
                else if node.type == "action" then
                  ''
                    echo -e "''${YELLOW}Action Required: ${node.text}''${NC}"
                    echo "Command: ${node.command}"

                    if [ -z "$DIAGNOSE_NON_INTERACTIVE" ]; then
                       read -p "Run this command now? [y/n]> " response
                       if [[ "$response" =~ ^[Yy] ]]; then
                         ${node.command}
                       fi
                    fi
                    CURRENT_NODE="${node.next or "END"}"
                  ''
                else if node.type == "result" then
                  ''
                    echo "----------------------------------------"
                    echo -e "''${GREEN}Diagnosis Complete''${NC}"
                    echo "${node.text}"
                    CURRENT_NODE="END"
                  ''
                else
                  ''
                    echo "Unknown node type: ${node.type}"
                    exit 1
                  ''
              }
              ;;
          ''
        ) (lib.attrNames tree.nodes)}
        *)
          echo "Error: Unknown node $CURRENT_NODE"
          exit 1
          ;;
      esac
    done
  '';
}

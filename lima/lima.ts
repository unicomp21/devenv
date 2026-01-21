#!/usr/bin/env -S deno run --allow-all

// Lima VM management script

// Set LIMA_HOME to VM directory for all persistence concerns
Deno.env.set("LIMA_HOME", "/Volumes/MacOS/Lima/VM");

const args = Deno.args;

async function runLimaCommand(args: string[]) {
    const cmd = new Deno.Command("limactl", {
        args: args,
        stdout: "inherit",
        stderr: "inherit",
        stdin: "inherit",
    });
    
    const result = await cmd.output();
    return result.code;
}

async function main() {
    if (args.length === 0) {
        console.log("Lima VM Manager");
        console.log(`LIMA_HOME: ${Deno.env.get("LIMA_HOME")}`);
        console.log("\nUsage:");
        console.log("  ./lima start      - Start the VM");
        console.log("  ./lima stop       - Stop the VM");
        console.log("  ./lima shell      - Connect to VM shell");
        console.log("  ./lima status     - Show VM status");
        console.log("  ./lima delete     - Delete the VM");
        console.log("  ./lima <cmd>      - Run any limactl command");
        Deno.exit(0);
    }
    
    const command = args[0];
    
    switch (command) {
        case "start":
            console.log("Starting Lima VM...");
            await runLimaCommand(["start", "default"]);
            break;
            
        case "stop":
            console.log("Stopping Lima VM...");
            await runLimaCommand(["stop", "default"]);
            break;
            
        case "shell":
            await runLimaCommand(["shell", "default"]);
            break;
            
        case "status":
            await runLimaCommand(["list"]);
            break;
            
        case "delete":
            console.log("Deleting Lima VM...");
            await runLimaCommand(["delete", "--force", "default"]);
            break;
            
        default:
            // Pass through any other limactl commands
            const exitCode = await runLimaCommand(args);
            Deno.exit(exitCode);
    }
}

await main(); 
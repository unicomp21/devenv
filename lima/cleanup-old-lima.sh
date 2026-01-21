#!/usr/bin/env -S deno run --allow-all

// Cleanup script to remove old Lima instances from default location

const { exit } = Deno;

async function runCommand(cmd: string[]): Promise<{ success: boolean; output: string }> {
    try {
        const process = new Deno.Command(cmd[0], {
            args: cmd.slice(1),
            stdout: "piped",
            stderr: "piped",
        });
        
        const { code, stdout, stderr } = await process.output();
        const output = new TextDecoder().decode(stdout) + new TextDecoder().decode(stderr);
        
        return { success: code === 0, output };
    } catch (error) {
        return { success: false, output: error.toString() };
    }
}

async function main() {
    console.log("Checking for existing Lima instances in default location...");
    
    // Check if lima is installed
    const limaCheck = await runCommand(["which", "limactl"]);
    if (!limaCheck.success) {
        console.log("Lima is not installed. Nothing to clean up.");
        exit(0);
    }
    
    // List instances in default location (without LIMA_HOME set)
    const envVars = { ...Deno.env.toObject() };
    delete envVars.LIMA_HOME;  // Remove LIMA_HOME to check default location
    
    const listCmd = new Deno.Command("limactl", {
        args: ["list", "--json"],
        env: envVars,
        stdout: "piped",
        stderr: "piped",
    });
    
    const listResult = await listCmd.output();
    
    if (listResult.code === 0) {
        const output = new TextDecoder().decode(listResult.stdout);
        try {
            const instances = JSON.parse(output);
            
            if (instances.length > 0) {
                console.log(`Found ${instances.length} instance(s) in default location:`);
                
                for (const instance of instances) {
                    console.log(`- ${instance.name} (${instance.status})`);
                    console.log(`Deleting instance '${instance.name}'...`);
                    
                    const deleteCmd = new Deno.Command("limactl", {
                        args: ["delete", "--force", instance.name],
                        env: envVars,
                        stdout: "inherit",
                        stderr: "inherit",
                    });
                    
                    const deleteResult = await deleteCmd.output();
                    
                    if (deleteResult.code === 0) {
                        console.log(`Successfully deleted '${instance.name}'`);
                    } else {
                        console.error(`Failed to delete '${instance.name}'`);
                    }
                }
            } else {
                console.log("No instances found in default location.");
            }
        } catch (e) {
            console.log("No instances found or unable to parse output.");
        }
    } else {
        console.log("Unable to list instances in default location.");
    }
    
    console.log("\nCleanup complete!");
}

await main(); 